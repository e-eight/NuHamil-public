module Profiler
  use omp_lib
  use ClassSys
  ! myrank/nprocs are always available: MPIFunction sets myrank=0, nprocs=1
  ! when the code is built without -DMPI, so per-rank profiling works in both
  ! the serial and the MPI build.
  use MPIFunction, only: myrank, nprocs
  implicit none

  public :: timer
  private
  type, private :: prof
    type(imap) :: counter
    type(dmap) :: timer
    real(8) :: start_time
  contains
    procedure :: init => InitProf
    procedure :: start => StartProf
    procedure :: fin => FinProf
    procedure :: add => AddProf
    procedure :: prt => PrintSummary
    procedure :: PrintMemoryUsage
  end type prof

  type(prof) :: timer
  type(sys) :: s

contains
  subroutine InitProf(this)
    class(prof), intent(inout) :: this

    ! All ranks accumulate their own timers so that per-rank work imbalance
    ! can be measured.  Rank 0 additionally prints the usual summary.
    this%start_time = omp_get_wtime()
    call this%counter%append(s%str('Total'),1)
    call this%timer%append(s%str('Total'),0.d0)
  end subroutine InitProf

  subroutine StartProf(this,key)
    class(prof), intent(inout) :: this
    type(str), intent(in) :: key
    call this%counter%append(key,0)
    call this%timer%append(key,0.d0)
  end subroutine StartProf

  subroutine AddProf(this,key,time_in)
    class(prof), intent(inout) :: this
    type(str), intent(in) :: key
    real(8), intent(in) :: time_in
    integer :: n
    real(8) :: time
    if(.not. this%counter%Search(key)) call this%start(key)
    n = this%counter%Get(key)
    time = this%timer%Get(key)
    call this%counter%append(key,n+1)
    call this%timer%append(key,time+time_in)
  end subroutine AddProf

  subroutine PrintMemoryUsage(this)
    ! only for linux, rank 0 only
    class(prof), intent(inout) :: this
    integer :: getpid
    character(512) :: c_num, fn_proc, cmd

    if(myrank /= 0) return
    write(c_num,'(i0)') getpid()
    fn_proc = '/proc/' // trim(c_num) // '/status'
    cmd = 'cat ' // trim(fn_proc) // ' | grep VmRSS'
    call system( trim(cmd) )
  end subroutine PrintMemoryUsage

  subroutine PrintSummary(this)
    class(prof), intent(inout) :: this
    integer :: n, i
    real(8) :: r, ttotal
    real(8) :: t_wall, t_acct, t_misc
    character(len=16) :: env_val
    integer :: env_len, env_stat
    logical :: dump_cat

    call this%timer%append(s%str('Total'),omp_get_wtime() - this%start_time)
    ttotal = this%timer%get(s%str('Total'))

    !--------------------------------------------------
    ! Rank 0: human readable summary (format unchanged)
    !--------------------------------------------------
    if (myrank==0) write(*,*)
    n = int(ttotal)
    if (myrank==0) write(*,'(a,i5,a,i2.2,a,i2.2)') &
        '    summary of time, total = ', n/3600, ':', &
        mod(n, 3600)/60, ':', mod(n, 60)
    if (myrank==0) write(*,*)
    if (myrank==0) write(*,'(37x,a)') "time,    ncall, time/ncall,   ratio "
    r = ttotal
    do i = 1, this%counter%GetLen()
      if(this%counter%key(i)%val == 'Total') cycle
      call PrintEach(this%counter%key(i)%val, this%counter%val(i), this%timer%val(i))
      r = r - this%timer%val(i)
    end do
    if (myrank==0) write(*,'(1a30, 1f12.3, 22x, 1f9.4)') &
        "misc", r, r/ttotal
    if (myrank==0)  write(*,*)

    !--------------------------------------------------
    ! Every rank: one machine readable totals line.  Parsed by
    ! bench/collect.py to compute the work imbalance factor
    ! max(acct)/mean(acct) over ranks.
    !
    ! wall : wall clock since timer%init() on this rank
    ! acct : sum of all accounted (category) timers on this rank
    ! misc : wall - acct  (may be negative if categories nest)
    !
    ! This must be called BEFORE mpi_finalize, otherwise non-zero ranks
    ! lose their stdout; NuHamilMain calls timer%fin() before mpi_finalize.
    !--------------------------------------------------
    t_wall = ttotal
    t_acct = 0.d0
    do i = 1, this%counter%GetLen()
      if(this%counter%key(i)%val == 'Total') cycle
      t_acct = t_acct + this%timer%val(i)
    end do
    t_misc = t_wall - t_acct
    write(*,'(a,i0,a,i0,a,f16.6,a,f16.6,a,f16.6)') &
        '#PROF_RANK ', myrank, ' ', nprocs, &
        ' wall ', t_wall, ' acct ', t_acct, ' misc ', t_misc

    !--------------------------------------------------
    ! Optional per-rank, per-category detail (set NUHAMIL_PROF_DUMP=1).
    !--------------------------------------------------
    dump_cat = .false.
    call get_environment_variable('NUHAMIL_PROF_DUMP', env_val, env_len, env_stat)
    if(env_stat == 0 .and. env_len >= 1) then
      if(env_val(1:1) == '1') dump_cat = .true.
    end if
    if(dump_cat) then
      do i = 1, this%counter%GetLen()
        if(this%counter%key(i)%val == 'Total') cycle
        write(*,'(a,i0,a,a,a,f16.6,a,i0)') &
            '#PROF_CAT ', myrank, ' ', trim(this%counter%key(i)%val), &
            ' ', this%timer%val(i), ' ', this%counter%val(i)
      end do
    end if
  contains
    subroutine PrintEach(title, ncall, time)
      character(*), intent(in) :: title
      integer, intent(in) :: ncall
      real(8), intent(in) :: time
      if (myrank==0) &
          write(*,'(1a30, 1f12.3, 1i10, 1f12.5, 1f9.4)') title,  &
          time, ncall, time/ncall, &
          time/ttotal
    end subroutine PrintEach

  end subroutine PrintSummary

  subroutine FinProf(this)
    class(prof), intent(inout) :: this
    call this%prt()
  end subroutine FinProf

end module Profiler

!program test_Profiler
!  use omp_lib
!  use Profiler, only: timer
!  implicit none
!  integer :: i, j, k
!  real(8) :: ti, tj, tk
!  real(8) :: wa
!  real(8), allocatable :: a(:), b(:)
!
!  call timer%init()
!  allocate(a(10000000))
!  a = 0.d0
!  call timer%cmemory(.true.,'a is allocated : ')
!  ti = omp_get_wtime()
!  allocate(b(100000000))
!  call timer%add("Allocation ", omp_get_wtime() - ti)
!  ti = omp_get_wtime()
!  b = 0.d0
!  call timer%add("All zero ", omp_get_wtime() - ti)
!  call timer%tmemory('b')
!
!
!  deallocate(a,b)
!
!  call timer%fin()
!
!end program test_Profiler
