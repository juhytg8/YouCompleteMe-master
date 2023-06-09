" This script is sourced while editing the .vim file with the tests.
" When the script is successful the .res file will be created.
" Errors are appended to the test.log file.
"
" To execute only specific test functions, add a second argument.  It will be
" matched against the names of the Test_ funtion.  E.g.:
"	../vim -Nu NONE vimrc -S lib/run_test.vim test_channel.vim open_delay
" The output can be found in the "messages" file.
"
" The test script may contain anything, only functions that start with
" "Test_" are special.  These will be invoked and should contain assert
" functions.  See test_assert.vim for an example.
"
" It is possible to source other files that contain "Test_" functions.  This
" can speed up testing, since Vim does not need to restart.  But be careful
" that the tests do not interfere with each other.
"
" If an error cannot be detected properly with an assert function add the
" error to the v:errors list:
"   call add(v:errors, 'test foo failed: Cannot find xyz')
"
" If preparation for each Test_ function is needed, define a SetUp function.
" It will be called before each Test_ function.
"
" If cleanup after each Test_ function is needed, define a TearDown function.
" It will be called after each Test_ function.
"
" When debugging a test it can be useful to add messages to v:errors:
"   call add(v:errors, "this happened")
"
" But for real debug logging:
"   call ch_log( ",,,message..." )
" Then view it in 'debuglog'

" Let a test take up to 1 minute
let s:single_test_timeout = 60000

" Restrict the runtimepath to the exact minimum needed for testing
let &rtp = getcwd() . '/lib'
set rtp +=$VIM/vimfiles,$VIMRUNTIME,$VIM/vimfiles/after

call ch_logfile( 'debuglog', 'w' )

" For consistency run all tests with 'nocompatible' set.
" This also enables use of line continuation.
set nocp

" Use utf-8 by default, instead of whatever the system default happens to be.
" Individual tests can overrule this at the top of the file.
set encoding=utf-8

" Avoid stopping at the "hit enter" prompt
set nomore

" Output all messages in English.
lang messages C

" Always use forward slashes.
set shellslash

func s:TestFailed()
  if pyxeval( '"ycm_state" in globals()' )
    let logs =  pyxeval( 'ycm_state.GetLogfiles()' )
    for log_name in sort( keys( logs ) )
      let log = readfile( logs[ log_name ] )
      let logfile = s:testid_filesafe . '_' . log_name . '.testlog'
      call writefile( log, logfile, 's' )
      call add( s:messages,
              \ 'Wrote '
              \ . log_name
              \ . ' log for failed test: '
              \ . logfile )
      call add( s:messages, '**** LOG FILE ' . log_name . ' ****' )
      call extend( s:messages, log )
    endfor
  endif
endfunc

func! Abort( timer_id )
  call assert_report( 'Test timed out!!!' )
  qa!
endfunc

func RunTheTest(test)
  echo 'Executing ' . a:test

  " Avoid stopping at the "hit enter" prompt
  set nomore

  " Avoid a three second wait when a message is about to be overwritten by the
  " mode message.
  set noshowmode

  " Clear any overrides.
  call test_override('ALL', 0)

  " Some tests wipe out buffers.  To be consistent, always wipe out all
  " buffers.
  %bwipe!

  " The test may change the current directory. Save and restore the
  " directory after executing the test.
  let save_cwd = getcwd()

  if exists("*SetUp_" . a:test)
    try
      exe 'call SetUp_' . a:test
    catch
      call add(v:errors,
            \ 'Caught exception in SetUp_' . a:test . ' before '
            \ . a:test
            \ . ': '
            \ . v:exception
            \ . ' @ '
            \ . g:testpath
            \ . ':'
            \ . v:throwpoint)
    endtry
  endif

  if exists("*SetUp")
    try
      call SetUp()
    catch
      call add(v:errors,
            \ 'Caught exception in SetUp() before '
            \ . a:test
            \ . ': '
            \ . v:exception
            \ . ' @ '
            \ . g:testpath
            \ . ':'
            \ . v:throwpoint)
    endtry
  endif

  call add(s:messages, 'Executing ' . a:test)
  let s:done += 1
  let timer = timer_start( s:single_test_timeout, funcref( 'Abort' ) )

  try
    let s:test = a:test
    let s:testid = g:testpath . ':' . a:test

    let test_filesafe = substitute( a:test, '[)(,:]', '_', 'g' )
    let s:testid_filesafe = g:testpath . '_' . test_filesafe

    au VimLeavePre * call EarlyExit(s:test)
    call ch_log( 'StartTest: ' . a:test )

    messages clear
    exe 'call ' . a:test
    " We require that tests either don't make errors or that they call messages
    " clear
    call assert_true(
          \ empty( execute( 'messages' ) ),
          \ 'Test '
          \ .. a:test
          \ .. ' produced unexpected messages output '
          \ .. string( execute( 'messages' ) )
          \ .. ' (hint: call :messages clear if this is expected, '
          \ .. 'or use :silent)' )

    call ch_log( 'EndTest: ' . a:test )
    au! VimLeavePre
  catch /^\cskipped/
    let v:errors = []
    call ch_log( 'Skipped: ' . a:test )
    call add(s:messages, '    Skipped')
    call add(s:skipped,
          \ 'SKIPPED ' . a:test
          \ . ': '
          \ . substitute(v:exception, '^\S*\s\+', '',  ''))
  catch
    call ch_log( 'Catch: ' . a:test )
    call add(v:errors,
          \ 'Caught exception in ' . a:test
          \ . ': '
          \ . v:exception
          \ . ' @ '
          \ . g:testpath
          \ . ':'
          \ . v:throwpoint)

    call s:TestFailed()
  endtry

  call timer_stop( timer )

  " In case 'insertmode' was set and something went wrong, make sure it is
  " reset to avoid trouble with anything else.
  set noinsertmode

  if exists("*TearDown")
    try
      call TearDown()
    catch
      call add(v:errors,
            \ 'Caught exception in TearDown() after ' . a:test
            \ . ': '
            \ . v:exception
            \ . ' @ '
            \ . g:testpath
            \ . ':'
            \ . v:throwpoint)
    endtry
  endif

  if exists("*TearDown_" . a:test)
    try
      exe 'call TearDown_' . a:test
    catch
      call add(v:errors,
            \ 'Caught exception in TearDown_' . a:test . ' after ' . a:test
            \ . ': '
            \ . v:exception
            \ . ' @ '
            \ . g:testpath
            \ . ':'
            \ . v:throwpoint)
    endtry
  endif

  " Clear any autocommands
  au!

  call test_override( 'ALL', 0 )
  %bwipe!

  " Close any extra tab pages and windows and make the current one not modified.
  while tabpagenr('$') > 1
    quit!
  endwhile

  while 1
    let wincount = winnr('$')
    if wincount == 1
      break
    endif
    bwipe!
    if wincount == winnr('$')
      " Did not manage to close a window.
      only!
      break
    endif
  endwhile

  exe 'cd ' . save_cwd
endfunc

func AfterTheTest()
  if len(v:errors) > 0
    let s:fail += 1
    call s:TestFailed()
    call add(s:errors, 'Found errors in ' . s:testid . ':')
    call extend(s:errors, v:errors)
    let v:errors = []
  endif
endfunc

func EarlyExit(test)
  " It's OK for the test we use to test the quit detection.
  call add(v:errors, 'Test caused Vim to exit: ' . a:test)
  call FinishTesting()
endfunc

" This function can be called by a test if it wants to abort testing.
func FinishTesting()
  call AfterTheTest()

  " Don't write viminfo on exit.
  set viminfo=

  if s:fail == 0
    " Success, create the .res file so that make knows it's done.
    call writefile( [], g:testname . '.res', 's' )
  endif

  if len(s:errors) > 0
    " Append errors to test.log
    let l = []
    if filereadable( 'test.log' )
      let l = readfile( 'test.log' )
    endif
    call writefile( l->extend( [ '', 'From ' . g:testpath . ':' ] )
                  \  ->extend( s:errors ),
                  \ 'test.log',
                  \ 's' )
  endif

  if s:done == 0
    let message = 'NO tests executed'
  else
    let message = 'Executed ' . s:done . (s:done > 1 ? ' tests' : ' test')
  endif
  echo message
  call add(s:messages, message)
  if s:fail > 0
    let message = s:fail . ' FAILED:'
    echo message
    call add(s:messages, message)
    call extend(s:messages, s:errors)
  endif

  " Add SKIPPED messages
  call extend(s:messages, s:skipped)

  " Append messages to the file "messages"
  let l = []
  if filereadable( 'messages' )
    let l = readfile( 'messages' )
  endif
  call writefile( l->extend( [ '', 'From ' . g:testpath . ':' ] )
                \  ->extend( s:messages ),
                \ 'messages',
                \ 's' )

  if exists( '$COVERAGE' ) && pyxeval( '_cov is not None' )
    pyx _cov.stop()
    pyx _cov.save()
  endif

  if s:fail > 0
    cquit!
  else
    qall!
  endif
endfunc

" Source the test script.  First grab the file name, in case the script
" navigates away.  g:testname can be used by the tests.
let g:testname = expand('%')
let g:testpath = expand('%:p')
let s:done = 0
let s:fail = 0
let s:errors = []
let s:messages = []
let s:skipped = []
try
  source %
catch
  let s:fail += 1
  call add(s:errors,
        \ 'Caught exception: ' .
        \ v:exception .
        \ ' @ ' . v:throwpoint)
endtry

" Locate Test_ functions and execute them.
redir @q
silent function /^Test_
redir END
let s:tests = split(substitute(@q, 'function \(\k*()\)', '\1', 'g'))

" If there is an extra argument filter the function names against it.
if argc() > 1
  let s:tests = filter(s:tests, 'v:val =~ argv(1)')
endif

pyx <<EOF
def _InitCoverage():
  try:
    import coverage
  except ImportError:
    return None

  cov = coverage.Coverage( data_file='.coverage.python', data_suffix = True )
  cov.start()
  return cov

import os
if 'COVERAGE' in os.environ:
  _cov = _InitCoverage()
EOF

" Init covimerage
if exists( '$COVERAGE' )
  profile start .vim_profile
  exe 'profile! file */youcompleteme.vim'
  exe 'profile! file */youcompleteme/**.vim'
endif

" Execute the tests in alphabetical order.
for s:test in sort(s:tests)
  " Silence, please!
  set belloff=all
  call RunTheTest(s:test)

  " Repeat a flaky test.  Give up when:
  " - $TEST_NO_RETRY is not empty
  " - $TEST_NO_RETRY is not 0
  " - it fails five times
  if len(v:errors) > 0
        \ && ( $TEST_NO_RETRY == '' || $TEST_NO_RETRY == '0' )
    for retry in range( 10 )
      call add( s:messages, 'Found errors in ' . s:test . '. Retrying.' )
      call extend( s:messages, v:errors )

      sleep 2

      let v:errors = []
      call RunTheTest(s:test)

      if len(v:errors) == 0
        " Test passed on rerun.
        break
      endif
    endfor
  endif

  call AfterTheTest()
endfor

call FinishTesting()

" vim: shiftwidth=2 sts=2 expandtab
