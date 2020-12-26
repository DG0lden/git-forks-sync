#!/usr/bin/env bash

set -e

#default values
FORCE_PUSH=false

function print_help() {
      echo "Syncs changes from upstream to origin git repository."
      echo "Possible parameters:"
      echo "    -h | --help      Print this help and exit"
      echo "    -f | --force     Force push upstream's version of branches with conflicts to origin"
      echo "    -u | --upstream  GIT checkout URL for upstream repository"
      echo "    -o | --origin    GIT checkout URL for origin repository"
}

while (( "$#" )); do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    -f|--force)
      FORCE_PUSH=true
      shift
      ;;
    -u|--upstream)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        UPSTREAM_URL=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -o|--origin)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        ORIGIN_URL=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
		echo
		print_help
        exit 1
      fi
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      echo
      print_help
      exit 1
      ;;
    *) # preserve positional arguments
      echo "Error: Unsupported flag $1" >&2
      echo
      print_help
      exit 1
      ;;
  esac
done

if [[ -z "${UPSTREAM_URL}" ]]; then
	echo "Error: Upstream URL is not set"
	echo
	print_help
	exit 1
fi
if [[ -z "${ORIGIN_URL}" ]]; then
	echo "Error: origin URL is not set"
	echo
	print_help
	exit 1
fi

REPO=$(basename "${UPSTREAM_URL}" .git)

echo "upstream is: ${UPSTREAM_URL}"
echo "origin is: ${ORIGIN_URL}"
echo "FORCE_PUSH is: ${FORCE_PUSH}"
echo "repo name is: ${REPO}"
#exit 1

#1. Зклонувати в нову папку форк без локального клона
TMPDIR=${TMP:-/tmp}/$(date +%Y-%m-%d-%H-%M)-${REPO}
echo "Workdir is: ${TMPDIR}"
mkdir -p ${TMPDIR}
cd ${TMPDIR}
git clone ${ORIGIN_URL} ${REPO}
cd ${REPO}

#10. Визначити локальний бранч
MAIN_BRANCH=$(git branch | grep \* | sed -e 's/^\* //')
echo "Main branch is: ${MAIN_BRANCH}"

#2. Підключити оригінал как апстрім
git remote add upstream ${UPSTREAM_URL}

#3. Зафетчити апстрім
git fetch origin
git fetch upstream

#4. Пройтись циклом по бранчам апстріма
for brname in $(git branch -r | grep upstream | cut -d/ -f2- | grep -v ^${MAIN_BRANCH}$ | grep -v HEAD | sort );
do
	#4.1. Створити локальну бранчу із апстріма
	echo "Using ${brname}"

	#4.2. Перевірити чи є така бранча на оріджині
	if git branch --track ${brname} origin/${brname} ; then
		#4.4. Якщо є - змерджити з апстрімом по фф
		echo "${brname} exists on origin, trying fast-forward merge"
		rm -r *
		git checkout ${brname}
		git reset --hard origin/${brname}
		if git merge --ff-only upstream/${brname} ; then
			#4.6. Якщо фф пройшов запушати результат в ориджін
			echo "${brname}: fast-forward merge successfully done"
			git push origin ${brname}
		else
			#4.5. Якщо фф не пройшов - записати в список на локальний мердж
			echo "${brname}: fast-forward merge failed, writing down branch to error list"
			if [[ "${FORCE_PUSH}" == "true" ]]; then
				echo "${brname}: force pushing ${brname} to origin"
				git checkout -b temp_force_push upstream/${brname}
				git push -f origin temp_force_push:${brname}
				git checkout ${brname}
				git reset --hard
				git branch -D temp_force_push
			else
				ERROR_LIST="${ERROR_LIST} ${brname}"
				git reset --hard
			fi
		fi
	else
		#4.3. Якщо немає, запушати її в ориджін
		echo "${brname} doesn't exist on origing, checking it out from upstream"
		rm -r *
		git checkout -b ${brname} upstream/${brname}
		git reset --hard upstream/${brname}
		git push -u origin
	fi
	echo "${brname} done"
	echo
	echo
done

echo "${MAIN_BRANCH} branch: trying fast-forward merge"
git checkout ${MAIN_BRANCH}
if git merge --ff-only upstream/${MAIN_BRANCH} ; then
	#4.6. Якщо фф пройшов запушати результат в ориджін
	echo "${MAIN_BRANCH}: fast-forward merge successfully done"
else
	#4.5. Якщо фф не пройшов - записати в список на локальний мердж
	echo "${MAIN_BRANCH}: fast-forward merge failed, writing down branch to error list"
	if [[ "${FORCE_PUSH}" == "true" ]]; then
		echo "${MAIN_BRANCH}: force pushing to origin"
		git checkout -b temp_main upstream/${MAIN_BRANCH}
		git push -f origin temp_main:${MAIN_BRANCH}
		git reset --hard
		git checkout ${MAIN_BRANCH}
		git branch -D temp_main
		git reset --hard
		git pull
	else
		ERROR_LIST="${ERROR_LIST} ${MAIN_BRANCH}"
	fi
fi
echo "${MAIN_BRANCH} branch done"
echo
echo

echo "All branches are done, pushing result to origin"
git push --all origin
git push --tags origin

if [[ "${ERROR_LIST}" != "" ]]; then
	echo "Following branches were not merged:"
	for brname in ${ERROR_LIST}; do
		echo "  - ${brname}"
	done
	echo "Repeat sync with --force option to force sync of these branches"
fi

echo
echo

#5. Видалити локальну репу
rm -rf ${TMPDIR}

