#!/bin/bash
#
# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

# Load the test setup defined in the parent directory
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/../integration_test_setup.sh" \
  || { echo "integration_test_setup.sh not found!" >&2; exit 1; }

# Returns 0 if gcov is not installed or if a version before 7.0 was found.
# Returns 1 otherwise.
function is_gcov_missing_or_wrong_version() {
  local -r gcov_location=$(which gcov)
  if [[ ! -x ${gcov_location:-/usr/bin/gcov} ]]; then
    echo "gcov not installed."
    return 0
  fi

  "$gcov_location" -version | grep "LLVM" && \
      echo "gcov LLVM version not supported." && return 0
  # gcov -v | grep "gcov" outputs a line that looks like this:
  # gcov (Debian 7.3.0-5) 7.3.0
  local gcov_version="$(gcov -v | grep "gcov" | cut -d " " -f 4 | cut -d "." -f 1)"
  [ "$gcov_version" -lt 7 ] \
      && echo "gcov versions before 7.0 is not supported." && return 0
  return 1
}

# Asserts if the given expected coverage result is included in the given output
# file.
#
# - expected_coverage The expected result that must be included in the output.
# - output_file       The location of the coverage output file.
function assert_coverage_result() {
    local expected_coverage="${1}"; shift
    local output_file="${1}"; shift

    # Replace newlines with commas to facilitate the assertion.
    local expected_coverage_no_newlines="$( echo "$expected_coverage" | tr '\n' ',' )"
    local output_file_no_newlines="$( cat "$output_file" | tr '\n' ',' )"

    (echo "$output_file_no_newlines" \
        | grep -F "$expected_coverage_no_newlines") \
        || fail "Expected coverage result
<$expected_coverage>
was not found in actual coverage report:
<$( cat "$output_file" )>"
}

# Returns the path of the code coverage report that was generated by Bazel by
# looking at the current $TEST_log. The method fails if TEST_log does not
# contain any coverage report for a passed test.
function get_coverage_file_path_from_test_log() {
  local ending_part="$(sed -n -e '/PASSED/,$p' "$TEST_log")"

  local coverage_file_path=$(grep -Eo "/[/a-zA-Z0-9\.\_\-]+\.dat$" <<< "$ending_part")
  [[ -e "$coverage_file_path" ]] || fail "Coverage output file does not exist!"
  echo "$coverage_file_path"
}

function test_sh_test_coverage() {
  cat <<EOF > BUILD
sh_test(
    name = "orange-sh",
    srcs = ["orange-test.sh"],
    data = ["//java/com/google/orange:orange-bin"]
)
EOF
  cat <<EOF > orange-test.sh
#!/bin/bash

java/com/google/orange/orange-bin
EOF
  chmod +x orange-test.sh

  mkdir -p java/com/google/orange

  cat <<EOF > java/com/google/orange/BUILD
package(default_visibility = ["//visibility:public"])

java_binary(
    name = "orange-bin",
    srcs = ["orangeBin.java"],
    main_class = "com.google.orange.orangeBin",
    deps = [":orange-lib"],
)

java_library(
    name = "orange-lib",
    srcs = ["orangeLib.java"],
)
EOF

  cat <<EOF > java/com/google/orange/orangeLib.java
package com.google.orange;

public class orangeLib {

  public void print() {
    System.out.println("orange prints a message!");
  }
}
EOF

  cat <<EOF > java/com/google/orange/orangeBin.java
package com.google.orange;

public class orangeBin {
  public static void main(String[] args) {
    orangeLib orange = new orangeLib();
    orange.print();
  }
}
EOF

  bazel coverage --test_output=all //:orange-sh &>$TEST_log || fail "Coverage for //:orange-sh failed"

  local coverage_file_path="$( get_coverage_file_path_from_test_log )"

  cat <<EOF > result.dat
SF:com/google/orange/orangeBin.java
FN:3,com/google/orange/orangeBin::<init> ()V
FN:5,com/google/orange/orangeBin::main ([Ljava/lang/String;)V
FNDA:0,com/google/orange/orangeBin::<init> ()V
FNDA:1,com/google/orange/orangeBin::main ([Ljava/lang/String;)V
FNF:2
FNH:1
DA:3,0
DA:5,4
DA:6,2
DA:7,1
LH:3
LF:4
end_of_record
SF:com/google/orange/orangeLib.java
FN:3,com/google/orange/orangeLib::<init> ()V
FN:6,com/google/orange/orangeLib::print ()V
FNDA:1,com/google/orange/orangeLib::<init> ()V
FNDA:1,com/google/orange/orangeLib::print ()V
FNF:2
FNH:2
DA:3,3
DA:6,3
DA:7,1
LH:3
LF:3
end_of_record
EOF
  diff result.dat "$coverage_file_path" >> $TEST_log
  cmp result.dat "$coverage_file_path" || fail "Coverage output file is different than the expected file"
}

function test_sh_test_coverage_cc_binary() {
  if is_gcov_missing_or_wrong_version; then
    echo "Skipping test." && return
  fi

  ########### Setup source files and BUILD file ###########
  cat <<EOF > BUILD
sh_test(
    name = "hello-sh",
    srcs = ["hello-test.sh"],
    data = ["//examples/cpp:hello-world"]
)
EOF
  cat <<EOF > hello-test.sh
#!/bin/bash

examples/cpp/hello-world
EOF
  chmod +x hello-test.sh

  mkdir -p examples/cpp

  cat <<EOF > examples/cpp/BUILD
package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "hello-world",
    srcs = ["hello-world.cc"],
    deps = [":hello-lib"],
)

cc_library(
    name = "hello-lib",
    srcs = ["hello-lib.cc"],
    hdrs = ["hello-lib.h"]
)
EOF

  cat <<EOF > examples/cpp/hello-world.cc
#include "examples/cpp/hello-lib.h"

#include <string>

using hello::HelloLib;
using std::string;

int main(int argc, char** argv) {
  HelloLib lib("Hello");
  string thing = "world";
  if (argc > 1) {
    thing = argv[1];
  }
  lib.greet(thing);
  return 0;
}
EOF

  cat <<EOF > examples/cpp/hello-lib.h
#ifndef EXAMPLES_CPP_HELLO_LIB_H_
#define EXAMPLES_CPP_HELLO_LIB_H_

#include <string>
#include <memory>

namespace hello {

class HelloLib {
 public:
  explicit HelloLib(const std::string &greeting);

  void greet(const std::string &thing);

 private:
  std::auto_ptr<const std::string> greeting_;
};

}  // namespace hello

#endif  // EXAMPLES_CPP_HELLO_LIB_H_
EOF

  cat <<EOF > examples/cpp/hello-lib.cc
#include "examples/cpp/hello-lib.h"

#include <iostream>

using std::cout;
using std::endl;
using std::string;

namespace hello {

HelloLib::HelloLib(const string& greeting) : greeting_(new string(greeting)) {
}

void HelloLib::greet(const string& thing) {
  cout << *greeting_ << " " << thing << endl;
}

}  // namespace hello
EOF

  ########### Run bazel coverage ###########
  bazel coverage --experimental_cc_coverage --test_output=all \
      //:hello-sh &>$TEST_log || fail "Coverage for //:orange-sh failed"

  ########### Assert coverage results. ###########
  local coverage_file_path="$( get_coverage_file_path_from_test_log )"
  local expected_result_hello_lib="SF:examples/cpp/hello-lib.cc
FN:18,_GLOBAL__sub_I_hello_lib.cc
FN:18,_Z41__static_initialization_and_destruction_0ii
FN:14,_ZN5hello8HelloLib5greetERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FN:11,_ZN5hello8HelloLibC2ERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNDA:1,_GLOBAL__sub_I_hello_lib.cc
FNDA:1,_Z41__static_initialization_and_destruction_0ii
FNDA:1,_ZN5hello8HelloLib5greetERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNDA:1,_ZN5hello8HelloLibC2ERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNF:4
FNH:4
DA:11,1
DA:12,1
DA:14,1
DA:15,1
DA:16,1
DA:18,3
LH:6
LF:6
end_of_record"
  assert_coverage_result "$expected_result_hello_lib" "$coverage_file_path"
  local coverage_result_hello_lib_header="SF:examples/cpp/hello-world.cc
FN:8,main
FNDA:1,main
FNF:1
FNH:1
DA:8,1
DA:9,2
DA:10,2
DA:11,1
DA:12,0
DA:14,1
DA:15,1
LH:6
LF:7
end_of_record"
  assert_coverage_result "$coverage_result_hello_lib_header" "$coverage_file_path"
}

function test_sh_test_coverage_cc_binary_and_java_binary() {
   if is_gcov_missing_or_wrong_version; then
    echo "Skipping test." && return
  fi

  ########### Setup source files and BUILD file ###########
  cat <<EOF > BUILD
sh_test(
    name = "hello-sh",
    srcs = ["hello-test.sh"],
    data = [
      "//examples/cpp:hello-world",
      "//java/com/google/orange:orange-bin"
    ]
)
EOF
  cat <<EOF > hello-test.sh
#!/bin/bash

examples/cpp/hello-world
java/com/google/orange/orange-bin
EOF
  chmod +x hello-test.sh

  mkdir -p examples/cpp

  cat <<EOF > examples/cpp/BUILD
package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "hello-world",
    srcs = ["hello-world.cc"],
    deps = [":hello-lib"],
)

cc_library(
    name = "hello-lib",
    srcs = ["hello-lib.cc"],
    hdrs = ["hello-lib.h"]
)
EOF

  cat <<EOF > examples/cpp/hello-world.cc
#include "examples/cpp/hello-lib.h"

#include <string>

using hello::HelloLib;
using std::string;

int main(int argc, char** argv) {
  HelloLib lib("Hello");
  string thing = "world";
  if (argc > 1) {
    thing = argv[1];
  }
  lib.greet(thing);
  return 0;
}
EOF

  cat <<EOF > examples/cpp/hello-lib.h
#ifndef EXAMPLES_CPP_HELLO_LIB_H_
#define EXAMPLES_CPP_HELLO_LIB_H_

#include <string>
#include <memory>

namespace hello {

class HelloLib {
 public:
  explicit HelloLib(const std::string &greeting);

  void greet(const std::string &thing);

 private:
  std::auto_ptr<const std::string> greeting_;
};

}  // namespace hello

#endif  // EXAMPLES_CPP_HELLO_LIB_H_
EOF

  cat <<EOF > examples/cpp/hello-lib.cc
#include "examples/cpp/hello-lib.h"

#include <iostream>

using std::cout;
using std::endl;
using std::string;

namespace hello {

HelloLib::HelloLib(const string& greeting) : greeting_(new string(greeting)) {
}

void HelloLib::greet(const string& thing) {
  cout << *greeting_ << " " << thing << endl;
}

}  // namespace hello
EOF

  ########### Setup Java sources ###########
  mkdir -p java/com/google/orange

  cat <<EOF > java/com/google/orange/BUILD
package(default_visibility = ["//visibility:public"])
java_binary(
    name = "orange-bin",
    srcs = ["orangeBin.java"],
    main_class = "com.google.orange.orangeBin",
    deps = [":orange-lib"],
)
java_library(
    name = "orange-lib",
    srcs = ["orangeLib.java"],
)
EOF

  cat <<EOF > java/com/google/orange/orangeLib.java
package com.google.orange;
public class orangeLib {
  public void print() {
    System.out.println("orange prints a message!");
  }
}
EOF

  cat <<EOF > java/com/google/orange/orangeBin.java
package com.google.orange;
public class orangeBin {
  public static void main(String[] args) {
    orangeLib orange = new orangeLib();
    orange.print();
  }
}
EOF

  ########### Run bazel coverage ###########
  bazel coverage --experimental_cc_coverage --test_output=all \
      //:hello-sh &>$TEST_log || fail "Coverage for //:orange-sh failed"

  ########### Assert coverage results. ###########
  local coverage_file_path="$( get_coverage_file_path_from_test_log )"
  local expected_result_hello_lib="SF:examples/cpp/hello-lib.cc
FN:18,_GLOBAL__sub_I_hello_lib.cc
FN:18,_Z41__static_initialization_and_destruction_0ii
FN:14,_ZN5hello8HelloLib5greetERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FN:11,_ZN5hello8HelloLibC2ERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNDA:1,_GLOBAL__sub_I_hello_lib.cc
FNDA:1,_Z41__static_initialization_and_destruction_0ii
FNDA:1,_ZN5hello8HelloLib5greetERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNDA:1,_ZN5hello8HelloLibC2ERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE
FNF:4
FNH:4
DA:11,1
DA:12,1
DA:14,1
DA:15,1
DA:16,1
DA:18,3
LH:6
LF:6
end_of_record"
  assert_coverage_result "$expected_result_hello_lib" "$coverage_file_path"

  local coverage_result_hello_lib_header="SF:examples/cpp/hello-world.cc
FN:8,main
FNDA:1,main
FNF:1
FNH:1
DA:8,1
DA:9,2
DA:10,2
DA:11,1
DA:12,0
DA:14,1
DA:15,1
LH:6
LF:7
end_of_record"
  assert_coverage_result "$coverage_result_hello_lib_header" "$coverage_file_path"


  ############# Assert Java code coverage results

  local coverage_result_orange_bin="SF:com/google/orange/orangeBin.java
FN:2,com/google/orange/orangeBin::<init> ()V
FN:4,com/google/orange/orangeBin::main ([Ljava/lang/String;)V
FNDA:0,com/google/orange/orangeBin::<init> ()V
FNDA:1,com/google/orange/orangeBin::main ([Ljava/lang/String;)V
FNF:2
FNH:1
DA:2,0
DA:4,4
DA:5,2
DA:6,1
LH:3
LF:4
end_of_record"
  assert_coverage_result "$coverage_result_orange_bin" "$coverage_file_path"

  local coverage_result_orange_lib="SF:com/google/orange/orangeLib.java
FN:2,com/google/orange/orangeLib::<init> ()V
FN:4,com/google/orange/orangeLib::print ()V
FNDA:1,com/google/orange/orangeLib::<init> ()V
FNDA:1,com/google/orange/orangeLib::print ()V
FNF:2
FNH:2
DA:2,3
DA:4,3
DA:5,1
LH:3
LF:3
end_of_record"
  assert_coverage_result "$coverage_result_orange_lib" "$coverage_file_path"
}

run_suite "test tests"
