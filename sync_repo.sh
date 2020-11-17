#!/usr/bin/env bash

set -e
FORCE_PUSH=true

GITHUB="git@github.com"
UPSTREAM_ORG="DG0lden"
ORIGIN_ORG="golubiev"
REPO="git-forks-sync"

UPSTREAM_URL=${GITHUB}:${UPSTREAM_ORG}/${REPO}.git
ORIGIN_URL=${GITHUB}:${ORIGIN_ORG}/${REPO}.git

echo "upstream is: ${UPSTREAM_URL}"
echo "origin is: ${ORIGIN_URL}"


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

