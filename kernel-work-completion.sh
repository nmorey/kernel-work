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

_kernel_work_backport_todo(){
    local OPT_LIST=$(_kernel_work_genoptlist kernel backport_todo)
    _get_comp_words_by_ref cur

    cd $LINUX_GIT/
    case "$prev" in
	-p|--path)
            compopt -o filenames +o nospace
	    COMPREPLY=( $( compgen -f  -- "$cur"))
	    ;;
	*)
	    __gitcomp_nl "$OPT_LIST"
	    ;;
    esac;
}

_kernel_work_build(){
    local OPT_LIST=$(_kernel_work_genoptlist kernel build)
    _get_comp_words_by_ref cur

    cd $LINUX_GIT/
    case "$prev" in
	-p|--path)
            compopt -o filenames +o nospace
	    COMPREPLY=( $( compgen -f  -- "$cur"))
	    ;;
	*)
	    __gitcomp_nl "$OPT_LIST"
	    ;;
    esac;
}

_kernel_work_extract_path(){
    local OPT_LIST=$(_kernel_work_genoptlist kernel extract_patch)
    _get_comp_words_by_ref cur

    case "$prev" in
	-p|--patch-path)
            compopt -o filenames +o nospace
	    COMPREPLY=( $( compgen -f  -- "$cur"))
	    ;;
	*)
	    __gitcomp_nl "$OPT_LIST"
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
		__gitcomp_nl "$(_kernel_work_genoptlist kernel)"
		return
		;;
	    *)
		__gitcomp_nl "$(kernel list_actions | grep -v list_actions)"
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

	    OPT_LIST=$(_kernel_work_genoptlist kernel $cmd_name)
	    case "$prev" in
		*)
		    __gitcomp_nl "$OPT_LIST"

	    esac
	fi
    fi

}

__kernel_work(){
    _kernel_work 0
} && complete -F __kernel_work kernel
