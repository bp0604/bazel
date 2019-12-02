// Copyright 2018 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
package com.google.devtools.build.lib.skyframe.actiongraph.v2;

import com.google.devtools.build.lib.analysis.AnalysisProtosV2.ActionGraphContainer;
import com.google.devtools.build.lib.analysis.AnalysisProtosV2.Target;
import com.google.devtools.build.lib.analysis.configuredtargets.RuleConfiguredTarget;
import com.google.devtools.build.lib.cmdline.Label;

/** Cache for RuleConfiguredTargets in the action graph. */
public class KnownRuleConfiguredTargets extends BaseCache<RuleConfiguredTarget, Target> {

  private final KnownRuleClassStrings knownRuleClassStrings;

  KnownRuleConfiguredTargets(
      ActionGraphContainer.Builder actionGraphBuilder,
      KnownRuleClassStrings knownRuleClassStrings) {
    super(actionGraphBuilder);
    this.knownRuleClassStrings = knownRuleClassStrings;
  }

  @Override
  Target createProto(RuleConfiguredTarget ruleConfiguredTarget, int id) {
    Label label = ruleConfiguredTarget.getLabel();
    String ruleClassString = ruleConfiguredTarget.getRuleClassString();
    Target.Builder targetBuilder = Target.newBuilder().setId(id).setLabel(label.toString());
    if (ruleClassString != null) {
      targetBuilder.setRuleClassId(knownRuleClassStrings.dataToId(ruleClassString));
    }
    return targetBuilder.build();
  }

  @Override
  void addToActionGraphBuilder(Target targetProto) {
    actionGraphBuilder.addTargets(targetProto);
  }
}