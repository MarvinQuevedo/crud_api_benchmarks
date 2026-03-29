program api_example
  implicit none

  integer, parameter :: MAX_ITEMS = 16
  integer, parameter :: NAME_LEN = 64
  integer, parameter :: DESC_LEN = 128

  type :: Item
    integer :: id = 0
    character(len=NAME_LEN) :: name = ''
    character(len=DESC_LEN) :: description = ''
    integer :: quantity = 0
    logical :: active = .false.
  end type Item

  type(Item), dimension(MAX_ITEMS) :: items
  integer :: next_id

  next_id = 1

  print *, 'Fortran API CRUD example (simulation only)'
  print *, '------------------------------------------'
  call handle_request('GET', '/health', '')
  call handle_request('POST', '/api/items', '{"name":"alpha","description":"demo","quantity":3}')
  call handle_request('GET', '/api/items/1', '')
  call handle_request('PUT', '/api/items/1', '{"name":"alpha","description":"updated","quantity":8}')
  call handle_request('GET', '/api/items?limit=50&offset=0', '')
  call handle_request('DELETE', '/api/items/1', '')
  call handle_request('GET', '/api/items/1', '')

contains

  subroutine handle_request(method, path, payload)
    character(len=*), intent(in) :: method, path, payload
    integer :: id

    select case (trim(method))
    case ('GET')
      if (trim(path) == '/health') then
        call respond(200, '{"status":"ok"}', method, path)
      else if (index(trim(path), '/api/items?') == 1 .or. trim(path) == '/api/items') then
        call list_items(method, path)
      else if (index(trim(path), '/api/items/') == 1) then
        id = parse_item_id(path)
        call get_item(id, method, path)
      else
        call respond(404, '{"error":"Not found"}', method, path)
      end if

    case ('POST')
      if (trim(path) == '/api/items') then
        call create_item(payload, method, path)
      else
        call respond(404, '{"error":"Not found"}', method, path)
      end if

    case ('PUT')
      if (index(trim(path), '/api/items/') == 1) then
        id = parse_item_id(path)
        call update_item(id, payload, method, path)
      else
        call respond(404, '{"error":"Not found"}', method, path)
      end if

    case ('DELETE')
      if (index(trim(path), '/api/items/') == 1) then
        id = parse_item_id(path)
        call delete_item(id, method, path)
      else
        call respond(404, '{"error":"Not found"}', method, path)
      end if

    case default
      call respond(405, '{"error":"Method not allowed"}', method, path)
    end select
  end subroutine handle_request

  subroutine list_items(method, path)
    character(len=*), intent(in) :: method, path
    integer :: i, total, first_idx
    character(len=512) :: body
    character(len=256) :: item_json

    total = 0
    first_idx = 0
    do i = 1, MAX_ITEMS
      if (items(i)%active) then
        total = total + 1
        if (first_idx == 0) first_idx = i
      end if
    end do

    if (first_idx == 0) then
      body = '{"items":[],"total":0}'
    else
      call item_to_json(items(first_idx), item_json)
      body = '{"items":[' // trim(item_json) // '],"total":' // trim(int_to_str(total)) // '}'
    end if
    call respond(200, trim(body), method, path)
  end subroutine list_items

  subroutine create_item(payload, method, path)
    character(len=*), intent(in) :: payload, method, path
    integer :: slot, q
    character(len=NAME_LEN) :: nm
    character(len=DESC_LEN) :: ds
    character(len=256) :: body

    call parse_payload(payload, nm, ds, q)
    if (len_trim(nm) == 0 .or. q < 0) then
      call respond(400, '{"error":"Invalid payload"}', method, path)
      return
    end if

    slot = first_empty_slot()
    if (slot == 0) then
      call respond(507, '{"error":"Storage full in demo"}', method, path)
      return
    end if

    items(slot)%id = next_id
    items(slot)%name = trim(nm)
    items(slot)%description = trim(ds)
    items(slot)%quantity = q
    items(slot)%active = .true.
    call item_to_json(items(slot), body)
    call respond(201, trim(body), method, path)
    next_id = next_id + 1
  end subroutine create_item

  subroutine get_item(id, method, path)
    integer, intent(in) :: id
    character(len=*), intent(in) :: method, path
    integer :: idx
    character(len=256) :: body

    idx = find_item(id)
    if (idx == 0) then
      call respond(404, '{"error":"Item not found"}', method, path)
      return
    end if

    call item_to_json(items(idx), body)
    call respond(200, trim(body), method, path)
  end subroutine get_item

  subroutine update_item(id, payload, method, path)
    integer, intent(in) :: id
    character(len=*), intent(in) :: payload, method, path
    integer :: idx, q
    character(len=NAME_LEN) :: nm
    character(len=DESC_LEN) :: ds
    character(len=256) :: body

    idx = find_item(id)
    if (idx == 0) then
      call respond(404, '{"error":"Item not found"}', method, path)
      return
    end if

    call parse_payload(payload, nm, ds, q)
    if (len_trim(nm) == 0 .or. q < 0) then
      call respond(400, '{"error":"Invalid payload"}', method, path)
      return
    end if

    items(idx)%name = trim(nm)
    items(idx)%description = trim(ds)
    items(idx)%quantity = q
    call item_to_json(items(idx), body)
    call respond(200, trim(body), method, path)
  end subroutine update_item

  subroutine delete_item(id, method, path)
    integer, intent(in) :: id
    character(len=*), intent(in) :: method, path
    integer :: idx
    character(len=128) :: body

    idx = find_item(id)
    if (idx == 0) then
      call respond(404, '{"error":"Item not found"}', method, path)
      return
    end if

    items(idx)%active = .false.
    write (body, '(A,I0,A)') '{"deleted":true,"id":', id, '}'
    call respond(200, trim(body), method, path)
  end subroutine delete_item

  subroutine parse_payload(payload, name, description, quantity)
    character(len=*), intent(in) :: payload
    character(len=*), intent(out) :: name, description
    integer, intent(out) :: quantity

    name = extract_json_string(payload, '"name":"')
    description = extract_json_string(payload, '"description":"')
    quantity = extract_json_int(payload, '"quantity":')
  end subroutine parse_payload

  function parse_item_id(path) result(id)
    character(len=*), intent(in) :: path
    integer :: id
    integer :: io, start_pos
    character(len=32) :: number_chunk

    id = -1
    start_pos = len('/api/items/') + 1
    if (len_trim(path) < start_pos) return
    number_chunk = adjustl(path(start_pos:))
    read (number_chunk, *, iostat=io) id
    if (io /= 0) id = -1
  end function parse_item_id

  function first_empty_slot() result(slot)
    integer :: slot, i
    slot = 0
    do i = 1, MAX_ITEMS
      if (.not. items(i)%active) then
        slot = i
        return
      end if
    end do
  end function first_empty_slot

  function find_item(id) result(idx)
    integer, intent(in) :: id
    integer :: idx, i

    idx = 0
    do i = 1, MAX_ITEMS
      if (items(i)%active .and. items(i)%id == id) then
        idx = i
        return
      end if
    end do
  end function find_item

  subroutine item_to_json(rec, out)
    type(Item), intent(in) :: rec
    character(len=*), intent(out) :: out
    write (out, '(A,I0,A,A,A,A,A,I0,A)') &
      '{"id":', rec%id, ',"name":"', trim(rec%name), &
      '","description":"', trim(rec%description), '","quantity":', rec%quantity, '}'
  end subroutine item_to_json

  function extract_json_string(payload, key) result(value)
    character(len=*), intent(in) :: payload, key
    character(len=DESC_LEN) :: value
    integer :: start_pos, end_pos, from

    value = ''
    start_pos = index(payload, key)
    if (start_pos == 0) return
    from = start_pos + len_trim(key)
    end_pos = index(payload(from:), '"')
    if (end_pos <= 1) return
    value = payload(from:from + end_pos - 2)
  end function extract_json_string

  function extract_json_int(payload, key) result(number)
    character(len=*), intent(in) :: payload, key
    integer :: number
    integer :: start_pos, from, io
    character(len=32) :: chunk

    number = -1
    start_pos = index(payload, key)
    if (start_pos == 0) return
    from = start_pos + len_trim(key)
    chunk = adjustl(payload(from:))
    read (chunk, *, iostat=io) number
    if (io /= 0) number = -1
  end function extract_json_int

  function int_to_str(n) result(out)
    integer, intent(in) :: n
    character(len=24) :: out
    write (out, '(I0)') n
  end function int_to_str

  subroutine respond(code, body, method, path)
    integer, intent(in) :: code
    character(len=*), intent(in) :: body, method, path
    print '(A,1X,A,1X,A,1X,I0,2X,A)', trim(method), trim(path), '->', code, trim(body)
  end subroutine respond

end program api_example
