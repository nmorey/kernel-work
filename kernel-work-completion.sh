export _KERNEL_WORK_CMD_AWK=$(([ -f /bin/awk ] && echo "/bin/awk") || echo "/usr/bin/awk")
export _KERNEL_WORK_CMD_SORT=$(([ -f /bin/sort ] && echo "/bin/sort") || echo "/usr/bin/sort")
export _KERNEL_WORK_CMD_EGREP=$(([ -f /bin/grep ] && echo "/bin/grep -E") || echo "/usr/bin/grep -E")
export _KERNEL_WORK_CMD_SED=$(([ -f /bin/sed ] && echo "/bin/sed") || echo "/usr/bin/sed")

_kernel_work_genoptlist(){
    local COMMAND=$*
    ${COMMAND}  --help 2>&1 | \
	${_KERNEL_WORK_CMD_AWK} 'BEGIN { found = 0 } { if(found == 1) print $$0; if($$1 == "Options:") {found = 1}}' | \
	${_KERNEL_WORK_CMD_EGREP} -e "^[[:space:]]*--" -e "^[[:space:]]*-[a-zA-Z0-9]" | \
	${_KERNEL_WORK_CMD_SED} -e 's/^[[:space:]]*//' -e 's/^-[^-], //' | \
	${_KERNEL_WORK_CMD_AWK} '{ print $1}' | \
	${_KERNEL_WORK_CMD_SED} -e 's/^\(.*\)\[no-\]\(.*$\)/\1\2\n\1no-\2/' | \
	${_KERNEL_WORK_CMD_SORT} -u
}

_kernel_work_opt_takes_arg(){
    local prev=$1
    shift
    local cmd=("$@")
    
    # 1. Get the option line
    local option_line=$("${cmd[@]}" --help 2>/dev/null | grep -E "([[:space:]]|^)$prev([^a-zA-Z0-9-]|$)" | head -n1)
    [ -z "$option_line" ] && return 1
    
    # 2. Extract option definition (before the description)
    local opt_def=$(echo "$option_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]\{2,\}.*$//')
    
    # 3. Check if it contains < or [
    if [[ "$opt_def" == *"<"* || "$opt_def" == *"["* ]]; then
        return 0
    fi
    return 1
}

_kernel_work_filter_opts(){
    local prev=$1
    shift
    local cmd=("$@")
    
    case "$prev" in
        -p|--path|-e|--exclude-path|--patch-path)
            compopt -o filenames +o nospace
            cd $LINUX_GIT/
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --filter)
            COMPREPLY=( $( compgen -W "$( ${words[0]} config filter list --raw 2>/dev/null )" -- "$cur" ) )
            return 0
            ;;
    esac

    if [[ "$cur" != -* ]] && _kernel_work_opt_takes_arg "$prev" "${cmd[@]}"; then
        COMPREPLY=()
        return 0
    fi
    return 1
}

_kernel_work_comp_nl(){
    __gitcomp_nl "$1" "" "$cur" ""
}

_kernel_work_backport_todo(){
    local OPT_LIST=$(_kernel_work_genoptlist kernel backport_todo)
    _get_comp_words_by_ref cur
    _get_comp_words_by_ref prev
    _get_comp_words_by_ref words

    _kernel_work_filter_opts "$prev" kernel backport_todo && return

    case "$prev" in
	*)
	    _kernel_work_comp_nl "$OPT_LIST"
	    ;;
    esac;
}

_kernel_work_config(){
    _get_comp_words_by_ref cur
    _get_comp_words_by_ref prev
    _get_comp_words_by_ref words
    _get_comp_words_by_ref cword

    if [ $cword -eq 2 ]; then
        _kernel_work_comp_nl "$(${words[0]} config list_actions)"
        return
    fi

    local sub_cmd=${words[2]}
    case "$sub_cmd" in
        filter)
            if [ $cword -eq 3 ]; then
                _kernel_work_comp_nl "$(${words[0]} config filter list_actions)"
                return
            fi
            local action=${words[3]}
            local opt_list=$(_kernel_work_genoptlist ${words[0]} config filter $action)
            _kernel_work_filter_opts "$prev" ${words[0]} config filter $action && return
            case "$prev" in
                -n|--name)
                    COMPREPLY=( $( compgen -W "$(${words[0]} config filter list --raw 2>/dev/null )" -- "$cur" ) )
                    ;;
                *)
                    _kernel_work_comp_nl "$opt_list"
                    ;;
            esac
            ;;
        branch)
            if [ $cword -eq 3 ]; then
                _kernel_work_comp_nl "$(${words[0]} config branch list_actions)"
                return
            fi
            local action=${words[3]}
            local opt_list=$(${words[0]}_work_genoptlist ${words[0]} config branch $action)
            _kernel_work_filter_opts "$prev" ${words[0]} config branch $action && return
            case "$prev" in
                -b|--branch)
                    COMPREPLY=( $( compgen -W "$(${words[0]} config branch list --raw 2>/dev/null )" -- "$cur" ) )
                    ;;
                *)
                    _kernel_work_comp_nl "$opt_list"
                    ;;
            esac
            ;;
        *)
            ;;
    esac
}

_kernel_work_build(){
    local OPT_LIST=$(_kernel_work_genoptlist ${words[0]} build)
    _get_comp_words_by_ref cur

    _kernel_work_filter_opts "$prev" ${words[0]} build && return

    case "$prev" in
	*)
	    _kernel_work_comp_nl "$OPT_LIST"
	    ;;
    esac;
}

_kernel_work_extract_path(){
    local OPT_LIST=$(_kernel_work_genoptlist ${words[0]} extract_patch)
    _get_comp_words_by_ref cur

    _kernel_work_filter_opts "$prev" ${words[0]} extract_patch && return

    case "$prev" in
	*)
	    _kernel_work_comp_nl "$OPT_LIST"
	    ;;
    esac;
}

_kernel_work(){
    local direct_call=${1:-1}
    local cmd_word=$(expr $direct_call + 1)

    cword=$cmd_word

    __git_has_doubledash && return

    _get_comp_words_by_ref cur
    _get_comp_words_by_ref prev
    _get_comp_words_by_ref cword


    if [ $cword -eq $cmd_word ]; then
	case "$cur" in
	    -*)
		_kernel_work_comp_nl "$(_kernel_work_genoptlist ${words[0]})"
		return
		;;
	    *)
		_kernel_work_comp_nl "$(${words[0]} list_actions | grep -v list_actions)"
		return
		;;
	esac
    else
	_get_comp_words_by_ref words
	local cmd_name=${words[$cmd_word]}
	completion_func="_kernel_work_${cmd_name}"
	declare -f $completion_func > /dev/null
	if [ $? -ne 0 ]; then
	    completion_func="_complete_${cmd_name}Env"
	    declare -f $completion_func > /dev/null
	fi
	if [ $? -eq 0 ]; then
	    $completion_func
	else

	    OPT_LIST=$(_kernel_work_genoptlist ${words[0]} $cmd_name)
	    _kernel_work_filter_opts "$prev" ${words[0]} $cmd_name && return
	    case "$prev" in
		*)
		    _kernel_work_comp_nl "$OPT_LIST"

	    esac
	fi
    fi

}

__kernel_work(){
    _kernel_work 0
} && complete -F __kernel_work kernel
