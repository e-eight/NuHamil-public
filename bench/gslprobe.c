/* Which GSL entry point aborts on the flat40 arguments?
 *
 * flat40 aborted with "gsl: gamma.c:1454: ERROR: underflow" == gsl_sf_lngamma_complex_e.
 * Our code reaches GSL through a handful of bindings in MyLibrary.F90.  GSL's default
 * error handler aborts the process, so a plain call tells us nothing about which one.
 * Install a handler that prints and returns, then sweep each binding over the argument
 * ranges the flat40 run actually uses, and report every error.
 *
 * Compile: gcc -O2 gslprobe.c -lgsl -lgslcblas -lm
 */
#include <stdio.h>
#include <math.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_sf_bessel.h>
#include <gsl/gsl_sf_legendre.h>
#include <gsl/gsl_sf_gamma.h>
#include <gsl/gsl_sf_laguerre.h>
#include <gsl/gsl_sf_gegenbauer.h>

static int n_err = 0;

static void handler(const char *reason, const char *file, int line, int gsl_errno)
{
    printf("  ERROR  %-28s %s:%d  (%s)\n", "", file, line, reason);
    n_err++;
}

int main(void)
{
    gsl_error_handler_t *old = gsl_set_error_handler(handler);
    (void)old;

    /* argument grids spanning what init_zx_function / init_fkx_function /
       precalculations feed to GSL at Nmax up to 40 (L = Nmax+2 = 42) */
    double xs[] = {0.0, 1e-8, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 0.1, 0.5, 1.0, 5.0, 20.0, 42.0};
    int nxs = sizeof(xs) / sizeof(xs[0]);
    double arr[64];
    int l, i, m;

    printf("== gsl_sf_bessel_jl_array(l, x)   [spherical_bessel_ladder, 6b] ==\n");
    for (l = 0; l <= 42; l += 2) {
        for (i = 0; i < nxs; i++) {
            printf("jl_array l=%2d x=%-8g", l, xs[i]);
            n_err = 0;
            gsl_sf_bessel_jl_array(l, xs[i], arr);
            if (n_err == 0) printf(" ok\n");
        }
    }

    printf("== gsl_sf_bessel_jl(l, x)         [spherical_bessel_c, pre-6b path] ==\n");
    for (l = 0; l <= 42; l += 2) {
        for (i = 0; i < nxs; i++) {
            printf("jl       l=%2d x=%-8g", l, xs[i]);
            n_err = 0;
            (void)gsl_sf_bessel_jl(l, xs[i]);
            if (n_err == 0) printf(" ok\n");
        }
    }

    printf("== gsl_sf_legendre_Pl(l, x)       [legendre_polynomial] ==\n");
    for (l = 0; l <= 42; l += 2) {
        double z[] = {-1.0, -0.9, 0.0, 0.9, 1.0};
        for (i = 0; i < 5; i++) {
            printf("Pl       l=%2d x=%-8g", l, z[i]);
            n_err = 0;
            (void)gsl_sf_legendre_Pl(l, z[i]);
            if (n_err == 0) printf(" ok\n");
        }
    }

    printf("== gsl_sf_legendre_sphPlm(l, m, x) [assoc_legendre_spharm] ==\n");
    for (l = 0; l <= 42; l += 2) {
        for (m = 0; m <= l; m += (l > 8 ? 9 : 1)) {
            printf("sphPlm   l=%2d m=%2d x=0.9", l, m);
            n_err = 0;
            (void)gsl_sf_legendre_sphPlm(l, m, 0.9);
            if (n_err == 0) printf(" ok\n");
        }
    }

    printf("== gsl_sf_lngamma(x)              [ln_gamma, ho_radial_wf_norm] ==\n");
    {
        double g[] = {0.5, 1.5, 2.0, 10.5, 20.5, 42.5, 60.5, 120.5, 200.0, 1e4, 1e8, 1e300};
        int n = sizeof(g) / sizeof(g[0]);
        for (i = 0; i < n; i++) {
            printf("lngamma  x=%-10g", g[i]);
            n_err = 0;
            (void)gsl_sf_lngamma(g[i]);
            if (n_err == 0) printf(" ok\n");
        }
    }

    printf("== gsl_sf_laguerre_n(n, a, x)     [laguerre] ==\n");
    for (l = 0; l <= 42; l += 6) {
        printf("laguerre n=%2d a=0  x=1.0", l);
        n_err = 0;
        (void)gsl_sf_laguerre_n(l, 0.0, 1.0);
        if (n_err == 0) printf(" ok\n");
    }

    printf("== gsl_sf_gegenpoly_n(n, l, x)    [Gegenbauer_polynomial] ==\n");
    for (l = 0; l <= 42; l += 6) {
        printf("gegen    n=%2d l=0.5 x=0.9", l);
        n_err = 0;
        (void)gsl_sf_gegenpoly_n(l, 0.5, 0.9);
        if (n_err == 0) printf(" ok\n");
    }

    printf("\nno error handler installed would have aborted on the first ERROR line above.\n");
    return 0;
}
