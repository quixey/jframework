/*
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
*/

Package.describe({
    summary: "JFramework for Meteor + React",
    name: "quixey:jframework",
    version: "1.1.94",
    git: "https://github.com/quixey/jframework.git"
});

Npm.depends({
    "react-router": "0.11.6"
});

Package.onUse(function(api) {
    api.versionsFrom("1.0.2.1");

    // Sets up window.ReactRouter
    api.addFiles(
        '.npm/package/node_modules/react-router/dist/react-router.js', 'client'
    );


    /*
        For used packages like "mongo" which use Tracker, we monkey patch it to
        use our version of the Tracker.* functions.
        For users of jframework, they only see our exported version of Tracker.
    */
    api.use("tracker");

    api.use([
        "meteor",
        "webapp",
        "logging",
        "ddp",
        "mongo",
        "check",
        "underscore",
        "jquery",
        "random",
        "ejson",
        "coffeescript",
        "reload",
        "autoupdate",
        "quixey:react@0.12.2"
    ]);

    api.imply([
        "meteor",
        "webapp",
        "logging",
        "ddp",
        "mongo",
        "check",
        "underscore",
        "jquery",
        "random",
        "ejson",
        "quixey:react@0.12.2"
    ]);

    api.addFiles([
        "lib/date.js",
        "lib/URI.js",
        "tracker.coffee",
        "j.coffee",
        "util.coffee",
        "var.coffee",
        "autovar.coffee",
        "dict.coffee",
        "list.coffee",
        "autodict.coffee",
        "autolist.coffee",
        "components.coffee",
        "proptypes.coffee",
        "models.coffee",
        "denorm.coffee",
        "routing.coffee",
        "dom.coffee"
    ]);

    api.addFiles([
        "components/AreYouSure.coffee",
        "components/Button.coffee",
        "components/CancelButton.coffee",
        "components/Dropdown.coffee",
        "components/DeleteButton.coffee",
        "components/EditButton.coffee",
        "components/Expandable.coffee",
        "components/KeyValueTable.coffee",
        "components/LinkButton.coffee",
        "components/Loader.coffee",
        "components/SubmitCancelDelete.coffee",
        "components/TableRow.coffee",
        "components/TextBox.coffee"
    ]);

    api.addFiles([
        "publish.coffee"
    ], "server");

    api.addFiles([
        "fetching.coffee"
    ], "client");

    api.export("Tracker");
    api.export("J");
    api.export("$$");
});

Package.onTest(function(api) {
    api.use([
        "tinytest",
        "quixey:jframework",
        "coffeescript",
        "insecure"
    ]);

    api.imply([
        "tinytest",
        "quixey:jframework"
    ]);

    api.addFiles([
        "tests/util-tests.coffee",
        "tests/test-models.coffee",
        "tests/autovar-tests.coffee",
        "tests/list-tests.coffee",
        "tests/dict-tests.coffee",
        "tests/jframework-tests.coffee"
    ]);

    api.addFiles([
        "tests/publish-tests.coffee",
        "tests/jframework-client-tests.coffee"
    ], "client");
});