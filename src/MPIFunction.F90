module MPIFunction
#ifdef MPI
  use mpi
#endif
  use omp_lib
  implicit none
  integer :: myrank = 0, nprocs = 1, ierr = 0
#ifdef MPI
  integer :: idest, idummy
  integer :: istatus(mpi_status_size)
  integer :: procs
#endif
contains
  subroutine parent_child_procedure(Method, ntotal, slranks, time)
    interface
      subroutine Method(cnt)
        integer, intent(in) :: cnt
      end subroutine Method
    end interface
    integer, intent(in) :: ntotal
    integer, allocatable, intent(inout) :: slranks(:)
    integer :: num_loops
    real(8), intent(out) :: time
    real(8) :: t0
#ifdef MPI
    integer :: i
#endif

    if(.not.allocated(slranks)) allocate(slranks(ntotal))
    slranks = 0
    time = 0.d0
    ! Per-unit timing.  The farm time reported elsewhere is the makespan -- every
    ! rank exits in the master's finalize sweep -- so it cannot show how unequal
    ! the work units are or how they were split across ranks.  These lines are
    ! the only view of the unit cost distribution, and subdividing units (or
    ! ordering them) needs exactly that.
    if(nprocs==1) then
      do num_loops=1, ntotal
        t0 = omp_get_wtime()
        call Method(num_loops)
        write(*,'(a,i6,a,i6,a,f12.3)') '#PROF_UNIT rank=', myrank, &
            & ' unit=', num_loops, ' sec=', omp_get_wtime()-t0
      end do
      return
    end if
    time = omp_get_wtime()
#ifdef MPI
    if(myrank == 0)then
      write(*,*)
      write(*,'(a)')"Parent-child procedure"
      write(*,'(a, i8)')"Total # of sets = ", ntotal
    end if
    call mpi_barrier(mpi_comm_world, ierr)
#endif
    if(myrank == 0) then
      do num_loops = 1, ntotal
#ifdef MPI
        call mpi_recv(idummy,1,mpi_integer,mpi_any_source,1,mpi_comm_world,istatus,ierr)
        idest = istatus(mpi_source)
        slranks(num_loops) = idest
        call mpi_send(num_loops,1,mpi_integer,idest,1,mpi_comm_world,ierr)
      end do
      do i = 1, nprocs-1 ! finalize process
        call mpi_recv(idummy,1,mpi_integer,mpi_any_source,1,mpi_comm_world,istatus,ierr)
        idest = istatus(mpi_source)
        num_loops = 0
        call mpi_send(num_loops,1,mpi_integer,idest,1,mpi_comm_world,ierr)
      end do
    else
      do
        call mpi_send(idummy,1,mpi_integer,0,1,mpi_comm_world,ierr)
        call mpi_recv(num_loops,1,mpi_integer,0,1,mpi_comm_world,istatus,ierr)
        if(num_loops == 0) exit
#endif
        t0 = omp_get_wtime()
        call Method(num_loops)
        write(*,'(a,i6,a,i6,a,f12.3)') '#PROF_UNIT rank=', myrank, &
            & ' unit=', num_loops, ' sec=', omp_get_wtime()-t0
      end do
    end if
#ifdef MPI
    call mpi_barrier(mpi_comm_world, ierr)
    if(myrank == 0) then
      write(*,'(a)')"End: Parent-child procedure"
    end if
#endif
    time = omp_get_wtime() - time
  end subroutine parent_child_procedure

  subroutine parent_child_procedure_data_transfer(Method, receive_data, ntotal, time)
    interface
      subroutine Method(cnt)
        integer, intent(in) :: cnt
      end subroutine Method

      subroutine receive_data()
      end subroutine receive_data
    end interface
    integer, intent(in) :: ntotal
    integer :: num_loops, n_run
    real(8), intent(out) :: time
    real(8) :: t0
    integer :: i_recv
#ifdef MPI
    integer :: i
#endif

    time = 0.d0
    ! Per-unit timing.  The farm time reported elsewhere is the makespan -- every
    ! rank exits in the master's finalize sweep -- so it cannot show how unequal
    ! the work units are or how they were split across ranks.  These lines are
    ! the only view of the unit cost distribution, and subdividing units (or
    ! ordering them) needs exactly that.
    if(nprocs==1) then
      do num_loops=1, ntotal
        t0 = omp_get_wtime()
        call Method(num_loops)
        write(*,'(a,i6,a,i6,a,f12.3)') '#PROF_UNIT rank=', myrank, &
            & ' unit=', num_loops, ' sec=', omp_get_wtime()-t0
      end do
      return
    end if
    time = omp_get_wtime()
#ifdef MPI
    if(myrank == 0)then
      write(*,*)
      write(*,'(a)')"Parent-child procedure"
      write(*,'(a, i8)')"Total # of sets = ", ntotal
    end if
    call mpi_barrier(mpi_comm_world, ierr)
#endif
    if(myrank == 0) then
      n_run = 0
      i_recv = 0
      do num_loops = 1, ntotal
#ifdef MPI
        call mpi_recv(idummy,1,mpi_integer,mpi_any_source,1,mpi_comm_world,istatus,ierr)
        idest = istatus(mpi_source)
        call mpi_send(num_loops,1,mpi_integer,idest,1,mpi_comm_world,ierr)
        n_run = n_run+1
        if(n_run >= nprocs-1) call receive_data()
      end do
      do i = 1, nprocs-2
        if(n_run >= nprocs-1) call receive_data()
      end do
      do i = 1, nprocs-1 ! finalize process
        call mpi_recv(idummy,1,mpi_integer,mpi_any_source,1,mpi_comm_world,istatus,ierr)
        idest = istatus(mpi_source)
        num_loops = 0
        call mpi_send(num_loops,1,mpi_integer,idest,1,mpi_comm_world,ierr)
      end do
    else
      do
        call mpi_send(idummy,1,mpi_integer,0,1,mpi_comm_world,ierr)
        call mpi_recv(num_loops,1,mpi_integer,0,1,mpi_comm_world,istatus,ierr)
        if(num_loops == 0) exit
#endif
        t0 = omp_get_wtime()
        call Method(num_loops)
        write(*,'(a,i6,a,i6,a,f12.3)') '#PROF_UNIT rank=', myrank, &
            & ' unit=', num_loops, ' sec=', omp_get_wtime()-t0
      end do
    end if
#ifdef MPI
    call mpi_barrier(mpi_comm_world, ierr)
    if(myrank == 0) then
      write(*,'(a)')"End: Parent-child procedure"
    end if
#endif
    time = omp_get_wtime() - time
  end subroutine parent_child_procedure_data_transfer
end module MPIFunction
