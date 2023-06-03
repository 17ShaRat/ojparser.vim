" Variables "{{{
let s:at_host = 'atcoder.jp'
let s:at_proto = 'https'
let s:at_path_regexp = '\([0-9]\+\)\/\?\([a-zA-Z][0-9]*\)\/\?[^/.]*\(\.[^.]\+\)$'

"}}}

function! atparser#ATLog(message, file) "{{{
    " from http://stackoverflow.com/questions/23089736/how-do-i-append-text-to-a-file-with-vim-script
	new
	setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
	put=a:message
	1d
	execute 'w ' a:file
	q
endfunction

"}}}
function! atparser#ATLoggedInAs() "{{{
    let at_response = system(printf("curl --silent --cookie-jar %s --cookie %s '%s://%s/' ", g:at_cookies_file, g:at_cookies_file, s:at_proto, s:at_host))
    if !empty(matchstr(at_response, "<a href=\"/[a-z0-9]*/logout\">"))
        return matchlist(at_response, "<a href=\"/users/\\([^\"]*\\)\">")[1]
    else
        return ""
    endif
endfunction

"}}}

function! atparser#ATParseTests(data) "{{{
    let input_regex = '<div class=\"input\">.\{-}<pre>\n*\(.\{-}\)</pre></div>'
    let output_regex = '<div class=\"output\">.\{-}<pre>\n*\(.\{-}\)</pre></div>'
    let ret = []
    let from = 0
    let text_substitutions = {
        \'<br[^>]\{-}>': '\n',
        \'&lt;': '<',
        \'&gt;': '>',
        \'&amp;': '&'
        \}
    while !empty(matchstr(a:data, input_regex, from))
        let input = matchlist(a:data, input_regex, from)[1]
        let from = matchend(a:data, input_regex, from)
        let output = matchlist(a:data, output_regex, from)[1]
        let from = matchend(a:data, output_regex, from)
        let input = cfparser#CFApplySubstitutions(input, text_substitutions)
        let output = cfparser#CFApplySubstitutions(output, text_substitutions)
        call add(ret, [input, output])
    endwhile
    return ret
endfunction

"}}}	
function! atparser#ATGetTests(contest, problem) "{{{
    let at_response = system(printf("curl --silent --cookie-jar %s --cookie %s '%s://%s/contest/%s/problem/%s'", g:at_cookies_file, g:at_cookies_file, s:at_proto, s:at_host, a:contest, a:problem))
	return cfparser#CFParseTests(cf_response)
endfunction

"}}}
function! atparser#ATApplySubstitutions(text, text_substitutions) "{{{
    let l:text = a:text
    for [pat, sub] in items(a:text_substitutions)
        let l:text = substitute(l:text, pat, sub, "g")
    endfor
    return l:text
endfunction

"}}}
function! atparser#ATGetToken(page) "{{{
    let g:ppage = a:page
    let match = matchlist(a:page, 'name=''csrf_token'' value=''\([^'']\{-}\)''')
    return match[1]
endfunction

"}}}
function! atparser#ATDownloadTests() "{{{
    let path = expand('%:p')
    let match = matchlist(path, s:at_path_regexp)
    
    if empty(match)        
        echom "download: file name not recognized"
    else
        let contest = match[1]
        let problem = match[2]
        echom printf("downloading tests for %s/%s...", contest, problem)
        let tests = atparser#ATGetTests(contest, problem)

		let cnt = 0
        for test in tests
			silent call atparser#ATLog(test[0], printf(expand('%:p:h') . "/%d.in", cnt))
			silent call atparser#ATLog(test[1], printf(expand('%:p:h') . "/%d.out", cnt))
            let cnt += 1
		endfor	
        echon "\r\r"
        echom printf("downloaded %d tests", cnt)
    endif
endfunction

"}}}
function! atparser#ATClearTests() "{{{
    echo system("rm *.in *.out")
    echom "cleared tests"
endfunction

"}}}
function! atparser#ATLogin() "{{{
    let s:at_uname = input('username: ')
    let s:at_passwd = inputsecret('password: ')
    let remember = input('remember? [Y/n] ')
    if remember ==? "Y"
        let s:at_remember = 1
    else
        let s:at_remember = 0
    endif

    let at_response = system(printf("curl --silent --cookie-jar %s '%s://%s/login'", g:at_cookies_file, s:at_proto, s:at_host))
    let csrf_token = atparser#ATGetToken(at_response)
    let at_response = system(printf("curl --location --silent --cookie-jar %s --cookie %s --data 'action=enter&username=%s&remember=%s&csrf_token=%s' --data-urlencode 'password=%s' '%s://%s/enter'", g:at_cookies_file, g:at_cookies_file, s:at_uname, s:at_remember, csrf_token, s:at_passwd, s:at_proto, s:at_host))
    echon "\r\r"
    if empty(matchstr(at_response, '"error for__password"'))
        echom "login: ok"
    else
        echom "login: failed"
    endif
endfunction

"}}}
function! atparser#ATLogout() "{{{
    if filereadable(g:at_cookies_file)
        call delete(g:at_cookies_file)
    endif
    echom "logout: ok"
endfunction

"}}}
function! atparser#ATWhoAmI() "{{{
    let user = atparser#ATLoggedInAs()
    if empty(user)
        echom ("not logged in")
    else
        echom printf("logged in as %s", atparser#ATLoggedInAs())
    endif
endfunction

"}}}
function! atparser#ATSubmit() "{{{
    if empty(atparser#ATLoggedInAs()) 
        call atparser#ATLogin()
    endif

    let path = expand('%:p')
    let match = matchlist(path, s:at_path_regexp)

    if empty(match)
        echon "\r\r"
        echom "submit: file name not recognized"
    else
        let contest = match[1]
        let problem = match[2]
        let extension = match[3]

        let language = g:cf_default_language
        if has_key(g:cf_pl_by_ext_custom, extension)
            let language = get(g:cf_pl_by_ext_custom, extension)
        elseif has_key(g:cf_pl_by_ext, extension)
            let language = get(g:cf_pl_by_ext, extension)
        endif

        let cf_response = system(printf("curl --silent --cookie-jar %s --cookie %s '%s://%s/contest/%s/submit'", g:cf_cookies_file, g:cf_cookies_file, s:cf_proto, s:cf_host, contest))
        let csrf_token = cfparser#CFGetToken(cf_response)

        let temp_file = expand("~/.cf_temp_file")
        silent call cfparser#CFLog(join(getline(1,'$'), "\n"), temp_file)
        let cf_response = system(printf("curl --location --silent --cookie-jar %s --cookie %s -F 'csrf_token=%s' -F 'action=submitSolutionFormSubmitted' -F 'submittedProblemIndex=%s' -F 'programTypeId=%s' -F \"source=@%s\" '%s://%s/contest/%s/submit?csrf_token=%s'", g:cf_cookies_file, g:cf_cookies_file, csrf_token, problem, language, temp_file, s:cf_proto, s:cf_host, contest, csrf_token))
        call delete(temp_file)
        echon "\r\r"
		if empty(cf_response)
			echom "submit: failed"
		else
			echom printf("submit: ok [by %s to %s/%s]", cfparser#CFLoggedInAs(), contest, problem)
        endif
    endif
endfunction

"}}}
function! cfparser#CFLastSubmissions(...) "{{{
    if a:0 < 1
        let handle = cfparser#CFLoggedInAs()
    else
        let handle = a:1
    endif

    let cf_response = system(printf("curl --location --silent '%s://%s/api/user.status?handle=%s&from=1&count=5'", s:cf_proto, s:cf_host, handle))
    let cf_response_json = parsejson#ParseJSON(cf_response)

    if empty(matchstr(cf_response_json.status, "OK"))
        echom "last submissions: failed"
    else
        let result = cf_response_json.result
        for sub in result
            echom printf("%d%s - %s - %s - Last Test: %d - %.3fMB - %dms", sub.problem.contestId, sub.problem.index, sub.problem.name, get(sub, 'verdict', 'UNKNOWN'), sub.passedTestCount, sub.memoryConsumedBytes / 1000000.0, sub.timeConsumedMillis)
        endfor
    endif
endfunction

"}}}
function! atparser#ATTestAll() "{{{
    echo system(printf("g++ %s -o ¬/tmp/cfparser_exec;
                        \cnt=0;
                        \for i in `ls %s/*.in | sed 's/\\.in$//'`; do
                        \   let cnt++;
                        \   echo \"\nTEST $cnt\";
                        \   ¬/tmp/cfparser_exec < $i.in | diff -y - $i.out;
                        \done;
                        \rm ¬/tmp/cfparser_exec",
        \ expand('%:p'), expand('%:p:h')))
endfunction

"}}}
function! cfparser#CFRun() "{{{
    echo system(printf("g++ %s -o ¬/tmp/cfparser_exec", expand('%s:p')))
    let saved_shellcmdflag = &shellcmdflag
        set shellcmdflag+=il
    try
        execute '!'. '¬/tmp/cfparser_exec'
    finally
        execute 'set shellcmdflag=' . saved_shellcmdflag
    endtry
    call system("rm ¬/tmp/cfparser_exec")
endfunction

"}}}
function! atparser#ATProblemStatement() "{{{
    let path = expand('%:p')
    let match = matchlist(path, s:at_path_regexp)

    if empty(match)
        echom "download: file name not recognized"
    else
        let contest = match[1]
        let problem = match[2]

		let at_response = system(printf("curl --silent --cookie-jar %s --cookie %s '%s://%s/contest/%s/problem/%s?locale=%s'", g:at_cookies_file, g:at_cookies_file, s:at_proto, s:at_host, contest, problem, g:at_locale))
        let at_response = substitute(at_response, '\r', '', "g")
        let statement_regex = '<div class="problem-statement">\(.\{-}\)<script type="text\/javascript">'
    	let cf_response = matchlist(cf_response, statement_regex)[1]
        let cf_response = substitute(cf_response,'<br[^>]\{-}>', '\n', "g")
        let cf_response = substitute(cf_response,'</div>', '\n', "g")
    	let cf_response = substitute(cf_response, '<.\{-}>', '', "g")
        let cf_response = substitute(cf_response, '&gt;', '>', "g")
        let cf_response = substitute(cf_response, '&lt;', '<', "g")
        let cf_response = substitute(cf_response, '&eq;', '=', "g")
        let cf_response = substitute(cf_response, '&amp;', '&', "g")
        let cf_response = substitute(cf_response, '&apos;', "'", "g")
        let cf_response = substitute(cf_response, '&quot;', '"', "g")
        
        vnew
        put=cf_response
        let name = contest . problem . "statement"
        execute 'file ' name
    endif
endfunction

"}}}
" vim:foldmethod=marker:foldlevel=0