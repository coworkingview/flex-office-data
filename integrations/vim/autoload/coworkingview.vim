" coworkingview.vim - fetch and render CoworkingView Price Index medians
" Maintainer: CoworkingView <info@coworkingview.com>
" License: MIT

" curl runs as an argument list, not a shell string. Neovim uses system();
" Vim 8.2 has no list form of system(), so it uses job_start(). Nothing here
" runs at load.

let s:version = '0.1.0'
let s:user_agent = 'coworkingview-vim/' . s:version
      \ . ' (+https://github.com/coworkingview/flex-office-data)'
let s:default_url = 'https://api.coworkingview.com/v1/market/rates'
let s:default_locale = 'en'
let s:product_order = [
      \ 'flex_desk',
      \ 'fix_desk',
      \ 'private_office',
      \ 'exclusive_bereich',
      \ 'day_pass',
      \ 'meeting_room',
      \ 'event_space',
      \ 'virtual_office',
      \ 'membership',
      \ ]
let s:stat_units = {
      \ 'day_pass': 'day',
      \ 'meeting_room': 'hour',
      \ 'event_space': 'hour',
      \ 'virtual_office': 'month',
      \ }
let s:cached_url = ''
let s:cached_at = -1
let s:cached_data = {}

function! coworkingview#reset() abort
  let s:cached_url = ''
  let s:cached_at = -1
  let s:cached_data = {}
endfunction

function! coworkingview#open(city) abort
  try
    call coworkingview#rate(a:city)
  catch /CoworkingView:/
    let l:message = matchstr(v:exception, 'CoworkingView:.*')
    if l:message ==# ''
      let l:message = v:exception
    endif
    echohl ErrorMsg
    echomsg l:message
    echohl None
  endtry
endfunction

function! coworkingview#rate(city) abort
  let l:data = s:load_data()
  call s:show(coworkingview#lines(a:city, l:data))
endfunction

" Vim passes the lead, the whole command line, and the cursor column.
function! coworkingview#complete(arglead, cmdline, cursorpos) abort
  if a:cursorpos < 0 && a:cmdline isnot# ''
    return []
  endif
  try
    let l:rows = s:rate_rows(s:load_data())
  catch /CoworkingView:/
    return []
  endtry
  let l:lead = tolower(trim(a:arglead))
  let l:slugs = []
  let l:seen = {}
  for l:row in l:rows
    if has_key(l:seen, l:row.city_slug)
      continue
    endif
    let l:seen[l:row.city_slug] = 1
    let l:name = tolower(trim(l:row.city_name))
    if l:lead ==# ''
          \ || stridx(tolower(l:row.city_slug), l:lead) == 0
          \ || stridx(l:name, l:lead) == 0
      call add(l:slugs, l:row.city_slug)
    endif
  endfor
  return sort(l:slugs)
endfunction

function! coworkingview#rows(data) abort
  return s:rate_rows(a:data)
endfunction

function! coworkingview#lines(query, data) abort
  let l:rows = s:rate_rows(a:data)
  let l:slug = s:match_city(l:rows, a:query)
  let l:city_rows = []
  for l:row in l:rows
    if l:row.city_slug ==# l:slug
      call add(l:city_rows, l:row)
    endif
  endfor
  let l:first = l:city_rows[0]
  let l:lines = []
  call add(l:lines, trim(l:first.city_name) . ' (' . l:first.city_slug . ')')
  let l:meta = 'currency: ' . l:first.currency
  if type(l:first.country_code) == v:t_string && l:first.country_code !=# ''
    let l:meta = 'country_code: ' . l:first.country_code . '  ' . l:meta
  endif
  call add(l:lines, l:meta)
  if type(l:first.as_of) == v:t_string && l:first.as_of !=# ''
    call add(l:lines, 'as_of: ' . l:first.as_of)
  endif
  call add(l:lines, '')
  let l:fmt = '%-18s %-6s %-16s %-12s %s'
  call add(l:lines, printf(
        \ l:fmt, 'product', 'unit', 'median', 'sample_size', 'low_confidence'))
  for l:row in l:city_rows
    call add(l:lines, printf(
          \ l:fmt,
          \ l:row.product,
          \ s:unit_text(l:row.unit),
          \ s:fmt_median(l:row),
          \ s:fmt_amount(l:row.sample_size),
          \ l:row.low_confidence ? 'true' : 'false'))
  endfor
  call add(l:lines, '')
  call add(l:lines, s:attribution_line(a:data))
  return l:lines
endfunction

" Seconds to wait before the single retry. Numeric Retry-After, else numeric
" RateLimit-Reset, else 2. Never more than 10.
function! coworkingview#retry_wait(headers) abort
  let l:wait = s:delay_seconds(s:header_value(a:headers, 'retry-after'))
  if l:wait is# v:null
    let l:wait = s:delay_seconds(s:header_value(a:headers, 'ratelimit-reset'))
  endif
  if l:wait is# v:null
    let l:wait = 2.0
  endif
  if l:wait > 10.0
    return 10.0
  endif
  if l:wait < 0.0
    return 0.0
  endif
  return l:wait + 0.0
endfunction

function! s:load_data() abort
  let l:url = s:rates_url()
  let l:ttl = s:cache_ttl()
  if s:cached_url ==# l:url && s:cached_at >= 0 && localtime() - s:cached_at < l:ttl
    return s:cached_data
  endif
  let l:result = s:http_get(l:url)
  if l:result.status < 200 || l:result.status >= 300
    call s:raise_http(l:result)
  endif
  let l:data = s:decode_success(l:result.body, l:result.status)
  let s:cached_url = l:url
  let s:cached_at = localtime()
  let s:cached_data = l:data
  return l:data
endfunction

function! s:rates_url() abort
  let l:base = ''
  if exists('g:coworkingview_api_url')
        \ && type(g:coworkingview_api_url) == v:t_string
        \ && g:coworkingview_api_url !=# ''
    let l:base = g:coworkingview_api_url
  elseif $COWORKINGVIEW_API_URL !=# ''
    let l:base = $COWORKINGVIEW_API_URL
  endif
  if l:base ==# ''
    let l:base = s:default_url
  endif
  let l:base = substitute(l:base, '/\+$', '', '')
  if l:base !~# '/v1/market/rates\%(?\|$\)'
    let l:base .= '/v1/market/rates'
  endif
  return s:with_locale(l:base)
endfunction

function! s:locale() abort
  if exists('g:coworkingview_locale')
        \ && type(g:coworkingview_locale) == v:t_string
        \ && g:coworkingview_locale =~# '^[A-Za-z0-9_-]\+$'
    return g:coworkingview_locale
  endif
  return s:default_locale
endfunction

" The live API rejects a rates request that does not name a locale.
function! s:with_locale(url) abort
  if a:url =~# '[?&]locale='
    return a:url
  endif
  let l:join = a:url =~# '?' ? '&' : '?'
  return a:url . l:join . 'locale=' . s:locale()
endfunction

function! s:cache_ttl() abort
  let l:ttl = get(g:, 'coworkingview_cache_seconds', 600)
  if type(l:ttl) == v:t_number
    return l:ttl
  endif
  if type(l:ttl) == v:t_float
    return float2nr(l:ttl)
  endif
  return 600
endfunction

function! s:curl_bin() abort
  if exists('g:coworkingview_curl')
        \ && type(g:coworkingview_curl) == v:t_string
        \ && g:coworkingview_curl !=# ''
    return g:coworkingview_curl
  endif
  return 'curl'
endfunction

function! s:http_get(url) abort
  let l:attempt = 0
  let l:result = {
        \ 'status': 0,
        \ 'body': '',
        \ 'headers': {},
        \ 'error': 'connection failed',
        \ }
  while l:attempt < 2
    let l:result = s:curl_once(a:url)
    let l:attempt += 1
    if s:retryable(l:result.status) && l:attempt == 1
      call s:sleep_seconds(coworkingview#retry_wait(l:result.headers))
      continue
    endif
    return l:result
  endwhile
  return l:result
endfunction

function! s:retryable(status) abort
  return a:status == 429 || (a:status >= 500 && a:status <= 599)
endfunction

function! s:curl_once(url) abort
  let l:body_file = tempname()
  let l:header_file = tempname()
  let l:error_file = tempname()
  let l:cmd = [
        \ s:curl_bin(),
        \ '-sS',
        \ '--max-time', '20',
        \ '--stderr', l:error_file,
        \ '-H', 'Accept: application/json',
        \ '-A', s:user_agent,
        \ '-D', l:header_file,
        \ '-o', l:body_file,
        \ '-w', '%{http_code}',
        \ '--',
        \ a:url,
        \ ]
  let l:ran = s:run(l:cmd)
  let l:out = l:ran.out
  let l:shell_error = l:ran.code
  let l:body = s:read_file(l:body_file)
  let l:header_text = s:read_file(l:header_file)
  let l:error_text = trim(s:read_file(l:error_file))
  call delete(l:body_file)
  call delete(l:header_file)
  call delete(l:error_file)
  if l:shell_error != 0
    if l:error_text ==# ''
      let l:error_text = 'curl exited ' . l:shell_error
    endif
    return {'status': 0, 'body': l:body, 'headers': {}, 'error': l:error_text}
  endif
  let l:status_text = trim(l:out)
  if l:status_text !~# '^[0-9]\+$'
    return {
          \ 'status': 0,
          \ 'body': l:body,
          \ 'headers': s:parse_headers(l:header_text),
          \ 'error': 'curl returned no HTTP status',
          \ }
  endif
  return {
        \ 'status': str2nr(l:status_text),
        \ 'body': l:body,
        \ 'headers': s:parse_headers(l:header_text),
        \ 'error': '',
        \ }
endfunction

" Run {cmd} (an argument list) without a shell. Returns out and exit code.
function! s:run(cmd) abort
  if has('nvim')
    let l:out = system(a:cmd)
    return {'out': l:out, 'code': v:shell_error}
  endif
  let l:stdout = tempname()
  let l:job = job_start(a:cmd, {
        \ 'out_io': 'file',
        \ 'out_name': l:stdout,
        \ 'err_io': 'null',
        \ 'mode': 'raw',
        \ })
  if job_status(l:job) ==# 'fail'
    call delete(l:stdout)
    return {'out': '', 'code': 1}
  endif
  let l:started = reltime()
  while job_status(l:job) ==# 'run'
    if reltimefloat(reltime(l:started)) > 25.0
      call job_stop(l:job, 'kill')
      call delete(l:stdout)
      return {'out': '', 'code': 1}
    endif
    sleep 20m
  endwhile
  let l:code = get(job_info(l:job), 'exitval', 1)
  let l:out = s:read_file(l:stdout)
  call delete(l:stdout)
  return {'out': l:out, 'code': l:code}
endfunction

function! s:read_file(path) abort
  if !filereadable(a:path)
    return ''
  endif
  return join(readfile(a:path), "\n")
endfunction

function! s:parse_headers(text) abort
  let l:headers = {}
  for l:line in split(a:text, "\n", 1)
    let l:line = substitute(l:line, '\r$', '', '')
    let l:colon = stridx(l:line, ':')
    if l:colon > 0
      let l:key = tolower(strpart(l:line, 0, l:colon))
      let l:headers[l:key] = trim(strpart(l:line, l:colon + 1))
    endif
  endfor
  return l:headers
endfunction

function! s:header_value(headers, name) abort
  if type(a:headers) != v:t_dict
    return v:null
  endif
  let l:want = tolower(a:name)
  for l:key in keys(a:headers)
    if tolower(l:key) ==# l:want
      return a:headers[l:key]
    endif
  endfor
  return v:null
endfunction

function! s:delay_seconds(value) abort
  if type(a:value) != v:t_string
    return v:null
  endif
  let l:text = trim(a:value)
  if l:text ==# '' || l:text !~# '^[0-9]\+\(\.[0-9]\+\)\?$'
    return v:null
  endif
  return str2float(l:text)
endfunction

function! s:sleep_seconds(seconds) abort
  let l:ms = float2nr((a:seconds * 1000.0) + 0.5)
  if l:ms < 1
    return
  endif
  if l:ms > 10000
    let l:ms = 10000
  endif
  execute 'sleep' l:ms . 'm'
endfunction

function! s:try_decode(body) abort
  try
    return json_decode(a:body)
  catch
    return v:null
  endtry
endfunction

function! s:decode_success(body, status) abort
  let l:parsed = s:try_decode(a:body)
  if l:parsed is# v:null
    call s:throw_error(
          \ a:status,
          \ 'BAD_RESPONSE',
          \ 'The API returned a body that is not valid JSON',
          \ '')
  endif
  if type(l:parsed) != v:t_dict
    call s:throw_error(
          \ a:status,
          \ 'BAD_RESPONSE',
          \ 'The API returned JSON that is not an object',
          \ '')
  endif
  let l:data = get(l:parsed, 'data', v:null)
  if type(l:data) != v:t_dict
    call s:throw_error(
          \ a:status,
          \ 'BAD_RESPONSE',
          \ 'The API returned JSON that is not an object',
          \ '')
  endif
  return l:data
endfunction

function! s:raise_http(result) abort
  if a:result.status == 0
    let l:detail = a:result.error
    if l:detail ==# ''
      let l:detail = 'connection failed'
    endif
    call s:throw_error(0, 'CONNECTION', l:detail, '')
  endif
  let l:code = 'HTTP_' . a:result.status
  let l:title = 'Request failed'
  let l:detail = ''
  let l:parsed = s:try_decode(a:result.body)
  if l:parsed is# v:null
    if trim(a:result.body) !=# ''
      let l:code = 'BAD_RESPONSE'
      let l:title = 'The API returned a body that is not valid JSON'
    endif
  elseif type(l:parsed) != v:t_dict
    let l:code = 'BAD_RESPONSE'
    let l:title = 'The API returned JSON that is not an object'
  else
    if type(get(l:parsed, 'code', v:null)) == v:t_string && l:parsed.code !=# ''
      let l:code = l:parsed.code
    endif
    if type(get(l:parsed, 'title', v:null)) == v:t_string && l:parsed.title !=# ''
      let l:title = l:parsed.title
    endif
    if type(get(l:parsed, 'detail', v:null)) == v:t_string
      let l:detail = l:parsed.detail
    endif
    let l:errors = s:error_text(l:parsed)
    if l:errors !=# ''
      if l:detail !=# ''
        let l:detail .= ' '
      endif
      let l:detail .= l:errors
    endif
  endif
  call s:throw_error(a:result.status, l:code, l:title, l:detail)
endfunction

function! s:error_text(problem) abort
  let l:errors = get(a:problem, 'errors', v:null)
  if type(l:errors) != v:t_list
    return ''
  endif
  let l:parts = []
  for l:item in l:errors
    if type(l:item) != v:t_dict
      continue
    endif
    let l:path = get(l:item, 'path', '')
    let l:message = get(l:item, 'message', '')
    if type(l:path) != v:t_string
      let l:path = ''
    endif
    if type(l:message) != v:t_string || l:message ==# ''
      continue
    endif
    if l:path !=# ''
      call add(l:parts, l:path . ': ' . l:message)
    else
      call add(l:parts, l:message)
    endif
  endfor
  return join(l:parts, '; ')
endfunction

function! s:throw_error(status, code, title, detail) abort
  if a:detail !=# ''
    throw printf(
          \ 'CoworkingView: %d %s: %s (%s)',
          \ a:status, a:code, a:title, a:detail)
  endif
  throw printf('CoworkingView: %d %s: %s', a:status, a:code, a:title)
endfunction

function! s:rate_rows(data) abort
  let l:rows = []
  if type(a:data) != v:t_dict
    return l:rows
  endif
  let l:cities = get(a:data, 'cities', [])
  if type(l:cities) != v:t_list
    return l:rows
  endif
  let l:as_of = get(a:data, 'asOf', v:null)
  if type(l:as_of) != v:t_string
    let l:as_of = v:null
  endif
  for l:city in l:cities
    if type(l:city) != v:t_dict
      continue
    endif
    call extend(l:rows, s:city_rows(l:city, l:as_of))
  endfor
  return s:sort_rows(l:rows)
endfunction

function! s:city_rows(city, as_of) abort
  let l:place = get(a:city, 'city', {})
  if type(l:place) != v:t_dict
    return []
  endif
  let l:slug = get(l:place, 'slug', '')
  if type(l:slug) != v:t_string || l:slug ==# ''
    return []
  endif
  let l:name = get(l:place, 'name', '')
  if type(l:name) != v:t_string
    let l:name = l:slug
  endif
  let l:currency = get(a:city, 'currency', '')
  if type(l:currency) != v:t_string
    let l:currency = ''
  endif
  let l:country = get(a:city, 'countryCode', v:null)
  if type(l:country) != v:t_string
    let l:country = v:null
  endif
  let l:rows = []
  for l:item in s:monthly_items(a:city)
    if type(l:item) != v:t_dict
      continue
    endif
    if type(get(l:item, 'optionType', v:null)) != v:t_string
      continue
    endif
    if !has_key(l:item, 'median')
      continue
    endif
    call add(l:rows, s:make_row(
          \ l:slug, l:name, l:country, l:currency,
          \ l:item.optionType, 'month', l:item, a:as_of))
  endfor
  for l:key in keys(a:city)
    let l:value = a:city[l:key]
    if !s:is_stat(l:value)
      continue
    endif
    let l:product = s:snake(l:key)
    let l:unit = get(s:stat_units, l:product, v:null)
    call add(l:rows, s:make_row(
          \ l:slug, l:name, l:country, l:currency,
          \ l:product, l:unit, l:value, a:as_of))
  endfor
  return l:rows
endfunction

function! s:monthly_items(city) abort
  let l:figures = get(a:city, 'figures', v:null)
  if type(l:figures) == v:t_list && !empty(l:figures)
    return l:figures
  endif
  let l:by_type = get(a:city, 'byType', v:null)
  if type(l:by_type) == v:t_list
    return l:by_type
  endif
  return []
endfunction

function! s:is_stat(value) abort
  return type(a:value) == v:t_dict
        \ && has_key(a:value, 'median')
        \ && has_key(a:value, 'sampleSize')
endfunction

function! s:snake(key) abort
  let l:out = ''
  for l:ch in split(a:key, '\zs')
    if l:ch =~# '[A-Z]' && l:out !=# ''
      let l:out .= '_'
    endif
    let l:out .= tolower(l:ch)
  endfor
  return l:out
endfunction

function! s:make_row(slug, name, country, currency, product, unit, item, as_of) abort
  let l:sample = s:sample_size(a:item)
  let l:money = get(a:item, 'median', {})
  let l:median_currency = a:currency
  if type(l:money) == v:t_dict
        \ && type(get(l:money, 'currency', v:null)) == v:t_string
    let l:median_currency = l:money.currency
  endif
  return {
        \ 'city_slug': a:slug,
        \ 'city_name': a:name,
        \ 'country_code': a:country,
        \ 'currency': a:currency,
        \ 'product': a:product,
        \ 'unit': a:unit,
        \ 'median': s:amount(l:money),
        \ 'median_currency': l:median_currency,
        \ 'sample_size': l:sample,
        \ 'low_confidence': s:as_float(l:sample) < 10.0,
        \ 'as_of': a:as_of,
        \ }
endfunction

function! s:amount(money) abort
  if type(a:money) != v:t_dict || !has_key(a:money, 'amount')
    return v:null
  endif
  return a:money.amount
endfunction

function! s:sample_size(item) abort
  let l:n = get(a:item, 'sampleSize', v:null)
  if type(l:n) == v:t_number
    return l:n
  endif
  if type(l:n) == v:t_float
    return float2nr(l:n)
  endif
  return 0
endfunction

function! s:as_float(n) abort
  if type(a:n) == v:t_number || type(a:n) == v:t_float
    return a:n + 0.0
  endif
  return 0.0
endfunction

function! s:sort_rows(rows) abort
  let l:keyed = {}
  let l:keys = []
  let l:index = 0
  for l:row in a:rows
    let l:key = s:sort_key(l:row, l:index)
    let l:keyed[l:key] = l:row
    call add(l:keys, l:key)
    let l:index += 1
  endfor
  let l:sorted = []
  for l:key in sort(l:keys)
    call add(l:sorted, l:keyed[l:key])
  endfor
  return l:sorted
endfunction

function! s:sort_key(row, index) abort
  let l:pos = index(s:product_order, a:row.product)
  if l:pos >= 0
    let l:rank = printf('0%02d', l:pos)
  else
    let l:rank = '1' . a:row.product
  endif
  return a:row.city_slug . "\n" . l:rank . "\n" . printf('%05d', a:index)
endfunction

function! s:match_city(rows, query) abort
  let l:query = tolower(trim(a:query))
  if l:query ==# ''
    throw 'CoworkingView: city is required'
  endif
  let l:slug_hit = ''
  let l:name_hits = []
  let l:seen = {}
  for l:row in a:rows
    if has_key(l:seen, l:row.city_slug)
      continue
    endif
    let l:seen[l:row.city_slug] = 1
    if tolower(l:row.city_slug) ==# l:query
      let l:slug_hit = l:row.city_slug
    endif
    if tolower(trim(l:row.city_name)) ==# l:query
      call add(l:name_hits, l:row.city_slug)
    endif
  endfor
  if l:slug_hit !=# ''
    return l:slug_hit
  endif
  if len(l:name_hits) == 1
    return l:name_hits[0]
  endif
  if len(l:name_hits) > 1
    throw printf('CoworkingView: ambiguous city "%s"', a:query)
  endif
  throw printf('CoworkingView: no published rates for city "%s"', a:query)
endfunction

function! s:fmt_amount(n) abort
  if type(a:n) == v:t_number
    return printf('%d', a:n)
  endif
  if type(a:n) == v:t_float
    if a:n == floor(a:n)
      return printf('%.0f', a:n)
    endif
    let l:text = printf('%.8f', a:n)
    let l:text = substitute(l:text, '0\+$', '', '')
    let l:text = substitute(l:text, '\.$', '', '')
    return l:text
  endif
  return ''
endfunction

function! s:fmt_median(row) abort
  let l:amount = s:fmt_amount(a:row.median)
  if l:amount ==# ''
    return ''
  endif
  if a:row.median_currency !=# ''
    return l:amount . ' ' . a:row.median_currency
  endif
  return l:amount
endfunction

function! s:unit_text(unit) abort
  if type(a:unit) == v:t_string
    return a:unit
  endif
  return ''
endfunction

function! s:attribution_line(data) abort
  let l:text = get(a:data, 'attribution', '')
  if type(l:text) == v:t_string && trim(l:text) !=# ''
    return l:text
  endif
  let l:license = get(a:data, 'licenseUrl', '')
  if type(l:license) != v:t_string || l:license ==# ''
    let l:license = 'https://creativecommons.org/licenses/by/4.0/'
  endif
  return 'Licensed under CC BY 4.0 (' . l:license . ').'
endfunction

function! s:show(lines) abort
  " A scheme keeps Vim from turning the name into a filesystem path.
  let l:nr = bufnr('^coworkingview://rates$')
  if l:nr == -1
    keepalt botright 12new
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nomodeline
    silent file coworkingview://rates
  else
    let l:win = bufwinnr(l:nr)
    if l:win == -1
      execute 'keepalt botright 12sbuffer' l:nr
    else
      execute l:win . 'wincmd w'
    endif
  endif
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nomodeline
  setlocal modifiable
  setlocal noreadonly
  silent %delete _
  call setline(1, a:lines)
  setlocal nomodifiable
  setlocal nomodified
  setlocal filetype=coworkingview
  call cursor(1, 1)
endfunction
