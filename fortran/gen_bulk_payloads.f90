program gen_bulk_payloads
  implicit none

  integer :: argc, n, i, q, ios
  character(len=256) :: arg_count, prefix
  character(len=512) :: line

  argc = command_argument_count()
  if (argc < 1) then
    write (0, *) 'Usage: gen_bulk_payloads COUNT [PREFIX]'
    stop 2
  end if

  call get_command_argument(1, arg_count)
  read (arg_count, *, iostat=ios) n
  if (ios /= 0 .or. n < 1) then
    write (0, *) 'Invalid COUNT: ', trim(arg_count)
    stop 2
  end if

  if (argc >= 2) then
    call get_command_argument(2, prefix)
  else
    prefix = 'bulk'
  end if
  prefix = trim(adjustl(prefix))

  do i = 1, n
    q = mod(i, 200)
    write (line, '(A,I0,A,I0,A)') '{"name":"' // trim(prefix) // '-', i, &
      '","description":"auto bulk","quantity":', q, '}'
    print '(A)', trim(line)
  end do

end program gen_bulk_payloads
