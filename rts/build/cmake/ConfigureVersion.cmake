# This file is part of the Spring engine (GPL v2 or later), see LICENSE.html

#
# example usage:
#Add_Custom_Command(
#	TARGET
#		configureVersion
#	COMMAND "${CMAKE_COMMAND}"
#		"-DSOURCE_ROOT=${CMAKE_SOURCE_DIR}"
#		"-DCMAKE_MODULES_SPRING=${CMAKE_MODULES_SPRING}"
#		"-DVERSION_ADDITIONAL=ABC"
#		"-DGENERATE_DIR=${CMAKE_BINARY_DIR}"
#		"-P" "${CMAKE_MODULES_SPRING}/ConfigureFile.cmake"
#	COMMENT
#		"Configure Version files" VERBATIM
#	)
#

cmake_minimum_required(VERSION 3.27)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_MODULES_SPRING}")

include(UtilVersion)



# Fetch through git or from the VERSION file
fetch_spring_version(${SOURCE_ROOT} SPRING_ENGINE)
parse_spring_version(SPRING_VERSION_ENGINE "${SPRING_ENGINE_VERSION}")

# AIRTS fork identity (see PATCHES.md, "Version identity").
# The branch part of the version string is replaced by "airts-<patch level>", read from
# airts/PATCH_LEVEL. Every build of one commit then has the same sync version whatever branch
# or detached HEAD it was built from, and no stock Recoil build can have the same string, so the
# server's client-version check keeps stock clients out of AIRTS games.
file(STRINGS "${SOURCE_ROOT}/airts/PATCH_LEVEL" AIRTS_PATCH_LEVEL LIMIT_COUNT 1 REGEX "^[0-9]+$")
if     ("${AIRTS_PATCH_LEVEL}" STREQUAL "")
	message(FATAL_ERROR "airts/PATCH_LEVEL is missing or does not hold a plain number")
endif  ()
if     ("${SPRING_VERSION_ENGINE_COMMITS}" STREQUAL "" OR "${SPRING_VERSION_ENGINE_HASH}" STREQUAL "")
	message(FATAL_ERROR "AIRTS builds need a git-describe version with commits and hash (got '${SPRING_ENGINE_VERSION}'); check out airts/main with tags, not an upstream release tag")
endif  ()
set(SPRING_VERSION_ENGINE_BRANCH "airts-${AIRTS_PATCH_LEVEL}")
create_spring_version_string(SPRING_ENGINE_VERSION
	"${SPRING_VERSION_ENGINE_MAJOR}" "${SPRING_VERSION_ENGINE_MINOR}" "${SPRING_VERSION_ENGINE_PATCH_SET}"
	"${SPRING_VERSION_ENGINE_COMMITS}" "${SPRING_VERSION_ENGINE_HASH}" "${SPRING_VERSION_ENGINE_BRANCH}")

# We define these, so it may be used in the to-be-configured files
set(SPRING_VERSION_ENGINE "${SPRING_ENGINE_VERSION}")
if     ("${SPRING_VERSION_ENGINE}" MATCHES "^${VERSION_REGEX_RELEASE}$")
	set(SPRING_VERSION_ENGINE_RELEASE 1)
else   ()
	set(SPRING_VERSION_ENGINE_RELEASE 0)
endif  ()

# This is supplied by -DVERSION_ADDITIONAL="abc"
set(SPRING_VERSION_ENGINE_ADDITIONAL "${VERSION_ADDITIONAL}")



message("Spring engine version: ${SPRING_ENGINE_VERSION} (${SPRING_VERSION_ENGINE_ADDITIONAL})")



file(MAKE_DIRECTORY "${GENERATE_DIR}/src-generated/engine/System")
configure_file(
		"${SOURCE_ROOT}/rts/System/VersionGenerated.h.template"
		"${GENERATE_DIR}/src-generated/engine/System/VersionGenerated.h"
		@ONLY
	)

file(MAKE_DIRECTORY "${GENERATE_DIR}")
configure_file(
		"${SOURCE_ROOT}/VERSION.template"
		"${GENERATE_DIR}/VERSION"
		@ONLY
	)
