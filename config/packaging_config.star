#!/usr/bin/env lucicfg
# Copyright 2020 The Flutter Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Configurations for packaging builders.

The schedulers pull commits indirectly from GoB repo (https://chromium.googlesource.com/external/github.com/flutter/flutter)
which is mirrored from https://github.com/flutter/flutter.
"""

load("//lib/common.star", "common")
load("//lib/repos.star", "repos")

def _setup(branches):
    shared_properties = {
        "shard": "packaging",
    }
    platform_args = {
        "linux": {
            "properties": shared_properties,
        },
        "mac": {
            "properties": shared_properties,
        },
        "windows": {
            "properties": shared_properties,
        },
    }

    packaging_recipe("ios-usb-dependencies", "")
    for branch in branches:
        # Skip packaging for master branch.
        if branch == "master" or branch == None:
            continue
        packaging_recipe("flutter", branches[branch]["version"])
        packaging_prod_config(
            platform_args,
            branch,
            branches[branch]["version"],
            branches[branch]["release-ref"],
        )

def recipe_name(name, version):
    return "%s%s" % (name, "_%s" % version if version else "")

def builder_name(pattern, branch):
    return pattern % (branch.capitalize(), branch)

def packaging_recipe(name, version):
    luci.recipe(
        name = recipe_name(name, version),
        cipd_package = "flutter/recipe_bundles/flutter.googlesource.com/recipes",
        cipd_version = "refs/heads/master",
    )

def packaging_prod_config(platform_args, branch, version, ref):
    """Prod configurations for packaging flutter framework artifacts.

    Args:
      platform_args(dict): Dictionary with default properties with platform as
        key.
      branch(str): The branch name we are creating configurations for.
      version(str): One of dev|beta|stable.
      ref(str): The git ref we are creating configurations for.
    """

    # Packaging should only build from release branches and never from master. This
    # is to prevent using excesive amount of resources to package something we will
    # never use.
    if branch == "master" or branch == None:
        fail("Packaging builders should not run on master changes")

    # Defines console views for prod builders
    console_view_name = ("packaging" if branch == "master" else "%s_packaging" % branch)
    luci.console_view(
        name = console_view_name,
        repo = repos.FLUTTER,
        refs = [ref],
    )

    # Defines prod schedulers
    trigger_name = branch + "-gitiles-trigger-packaging"
    luci.gitiles_poller(
        name = trigger_name,
        bucket = "prod",
        repo = repos.FLUTTER,
        refs = [ref],
    )

    # Defines triggering policy
    if branch == "master":
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 6,
        )
    else:
        triggering_policy = scheduler.greedy_batching(
            max_concurrent_invocations = 3,
        )

    # Defines framework prod builders
    common.linux_prod_builder(
        name = builder_name("Linux Flutter %s Packaging|%s", branch),
        recipe = recipe_name("flutter", version),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        **platform_args["linux"]
    )
    common.mac_prod_builder(
        name = builder_name("Mac Flutter %s Packaging|%s", branch),
        recipe = recipe_name("flutter", version),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        **platform_args["mac"]
    )
    common.windows_prod_builder(
        name = builder_name("Windows Flutter %s Packaging|%s", branch),
        recipe = recipe_name("flutter", version),
        console_view_name = console_view_name,
        triggered_by = [trigger_name],
        triggering_policy = triggering_policy,
        **platform_args["windows"]
    )

packaging_config = struct(setup = _setup)
