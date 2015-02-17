Package.describe({
    summary: "J Framework for Meteor + React",
    version: "0.0.1"
});

Npm.depends({
    // "react-router": "0.11.6"
});

Package.onUse(function(api) {
    // Sets up window.ReactRouter
    api.addFiles(
        // '.npm/package/node_modules/react-router/dist/react-router.js', 'client'
    );

    api.use([
        "underscore",
        "coffeescript",
        "quixey:react"
    ]);

    api.imply([
        "underscore",
        "quixey:react"
    ]);

    api.addFiles([
        "lib/date.js",
        "lib/URI.js",
        "j.coffee",
        "tracker.coffee",
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
        "routing.coffee"
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
        "insecure",
        "tinytest",
        "coffeescript",
        "jframework"
    ]);

    api.imply([
        "tinytest",
        "jframework"
    ]);

    api.addFiles([
        "tests/util-tests.coffee",
        "tests/test-models.coffee",
        //"tests/jframework-tests.coffee"
    ]);

    api.addFiles([
        "tests/publish-tests.coffee"
    ], "client");

    api.addFiles([
        // "tests/jframework-client-tests.coffee"
    ], "client");
});