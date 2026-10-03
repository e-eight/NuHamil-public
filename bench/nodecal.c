/* Node-speed calibration probe for the ICC scavenger pool.
 *
 * Why this exists
 * ---------------
 * scavenger nodes differ by up to **1.67x** in wall time for the *same* binary
 * on the *same* input (Intel Xeon 8358 vs AMD EPYC 9555; see docs/FINDINGS.md).
 * Scheduler placement is therefore a hidden variable in every comparison, and it
 * has already invalidated three sets of results.  Pairing every experiment on
 * one node is the safe answer but expensive, because queue time is the real
 * bottleneck here.
 *
 * This probe is the cheap alternative: a fixed, short (~20 s) amount of work,
 * run on any node, producing numbers that can be used as a normalisation
 * factor.  It reports three quantities because the workload is limited by more
 * than one thing:
 *
 *   gemm1   one-thread dgemm       -> single-core speed (clock/IPC/MKL kernels)
 *   gemmN   all-thread dgemm       -> aggregate flops + memory bandwidth
 *   triadN  OpenMP memory triad    -> streaming bandwidth, working set > L3
 *
 * The dgemm sizes put the operands (~2 x n^2 doubles) well beyond L3, which is
 * the regime that matters: the production case holds matrices of several GB.
 *
 * Caveat: this is a *proxy*.  Validate it against the nodes whose full-case
 * times are known before trusting it for anything below ~20 %.
 *
 * Usage: nodecal            (threads = OMP_NUM_THREADS, default = all)
 *        nodecal <threads>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

/* LP64 MKL: the BLAS integer arguments are plain 4-byte int.  This is the same
 * interface the NuHamil build relies on (see config/sites/icc.mk). */
extern void dgemm_(const char *, const char *, const int *, const int *,
                   const int *, const double *, const double *, const int *,
                   const double *, const int *, const double *, double *,
                   const int *);

static double now_s(void) { return omp_get_wtime(); }

static void *xmalloc(size_t n) {
    void *p = malloc(n);
    if (!p) {
        fprintf(stderr, "nodecal: out of memory (%zu bytes)\n", n);
        exit(1);
    }
    return p;
}

/* Fixed-work dgemm: operands of n x n, 'reps' repetitions.  Returns GFLOP/s. */
static double bench_gemm(int n, int reps, int nthreads) {
    const double one = 1.0, zero = 0.0;
    const int ld = n;
    size_t bytes = (size_t)n * (size_t)n * sizeof(double);
    double *a = xmalloc(bytes), *b = xmalloc(bytes), *c = xmalloc(bytes);
    double t0, t1, flops;

    omp_set_num_threads(nthreads);
#pragma omp parallel for schedule(static)
    for (size_t i = 0; i < (size_t)n * (size_t)n; i++) {
        a[i] = 1.0 / (double)(i % 97 + 1);
        b[i] = 1.0 / (double)(i % 89 + 1);
        c[i] = 0.0;
    }

    t0 = now_s();
    for (int r = 0; r < reps; r++)
        dgemm_("N", "N", &n, &n, &n, &one, a, &ld, b, &ld, &zero, c, &ld);
    t1 = now_s();

    flops = 2.0 * (double)n * (double)n * (double)n * (double)reps;
    /* keep one value live so the compiler cannot elide the product */
    if (c[0] == 12345.6789)
        fprintf(stderr, "unreachable %f\n", c[0]);

    free(a);
    free(b);
    free(c);
    return flops / (t1 - t0) / 1e9;
}

/* Streaming triad over a working set larger than L3.  Returns GB/s of traffic,
 * counting read a + read b + write c (the usual triad convention). */
static double bench_triad(size_t n, int reps, int nthreads) {
    double *a = xmalloc(n * sizeof(double));
    double *b = xmalloc(n * sizeof(double));
    double *c = xmalloc(n * sizeof(double));
    double t0, t1, bytes;

    omp_set_num_threads(nthreads);
#pragma omp parallel for schedule(static)
    for (size_t i = 0; i < n; i++) {
        a[i] = 1.0;
        b[i] = 2.0;
        c[i] = 0.0;
    }

    t0 = now_s();
    for (int r = 0; r < reps; r++) {
#pragma omp parallel for schedule(static)
        for (size_t i = 0; i < n; i++)
            c[i] = a[i] + 3.0 * b[i];
    }
    t1 = now_s();

    bytes = 3.0 * (double)n * sizeof(double) * (double)reps;
    if (c[0] == 12345.6789)
        fprintf(stderr, "unreachable %f\n", c[0]);

    free(a);
    free(b);
    free(c);
    return bytes / (t1 - t0) / 1e9;
}

static void cpu_model(char *out, size_t n) {
    FILE *f = fopen("/proc/cpuinfo", "r");
    out[0] = '\0';
    if (!f)
        return;
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "model name", 10) == 0) {
            char *p = strchr(line, ':');
            if (p) {
                p++;
                while (*p == ' ')
                    p++;
                size_t len = strcspn(p, "\n");
                if (len >= n)
                    len = n - 1;
                memcpy(out, p, len);
                out[len] = '\0';
            }
            break;
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    char model[256];
    int nth = omp_get_max_threads();
    if (argc > 1)
        nth = atoi(argv[1]);
    if (nth < 1)
        nth = 1;

    /* 1600^2 doubles = 20.5 MB per operand: comfortably past any L3 here. */
    const int gemm_n = 1600;
    const int gemm_reps = 3;
    /* 64M doubles = 512 MB per array -> ~1.5 GB touched per triad rep. */
    const size_t triad_n = (size_t)64 << 20;
    const int triad_reps = 4;
    /* Best-of-N, NOT the mean.  On a shared node the mean folds in other
     * tenants' load; the best sample approximates what the hardware can do.
     * The first version of this probe reported a single sample per metric and
     * failed validation: two nodes with the *same* CPU (ccc0497, ccc0499) came
     * out 1.31x apart on gemm1 and 3.5x apart on triad1, which can only be
     * contention, while their full-case times agreed to 2.8 %.  All samples are
     * printed so the spread is visible rather than hidden.  See docs/FINDINGS.md. */
    const int R = 5;

    cpu_model(model, sizeof(model));

    double g1 = 0.0, gN = 0.0, t1_ = 0.0, tN = 0.0;
    for (int r = 0; r < R; r++) {
        double v = bench_gemm(gemm_n, gemm_reps, 1);
        printf("NODECAL sample gemm1 %.3f\n", v);
        if (v > g1) g1 = v;
    }
    for (int r = 0; r < R; r++) {
        double v = bench_gemm(gemm_n, gemm_reps, nth);
        printf("NODECAL sample gemmN %.3f\n", v);
        if (v > gN) gN = v;
    }
    for (int r = 0; r < R; r++) {
        double v = bench_triad(triad_n, triad_reps, 1);
        printf("NODECAL sample triad1 %.3f\n", v);
        if (v > t1_) t1_ = v;
    }
    for (int r = 0; r < R; r++) {
        double v = bench_triad(triad_n, triad_reps, nth);
        printf("NODECAL sample triadN %.3f\n", v);
        if (v > tN) tN = v;
    }

    printf("#NODECAL host=%s\n",
           getenv("SLURMD_NODENAME") ? getenv("SLURMD_NODENAME") : "?");
    printf("#NODECAL cpu=%s\n", model);
    printf("#NODECAL threads=%d\n", nth);
    printf("#NODECAL reduce=best_of_%d\n", R);
    /* machine-readable lines; each metric is the best of the samples above */
    printf("NODECAL gemm1_gflops %.3f\n", g1);
    printf("NODECAL gemmN_gflops %.3f\n", gN);
    printf("NODECAL triad1_gbps %.3f\n", t1_);
    printf("NODECAL triadN_gbps %.3f\n", tN);
    return 0;
}
