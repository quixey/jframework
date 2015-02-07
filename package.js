Package.describe({
    summary: "J Framework for Meteor + React",
    version: "0.0.1"
});

Npm.depends({
    "react-router": "0.11.6"
});

Package.onUse(function(api) {
    api.use([
        "underscore",
        "coffeescript",
        "tracker",
        "reactive-var",
        "quixey:react"
    ]);

    api.imply([
        "underscore",
        "quixey:react"
    ]);

    // Sets up window.ReactRouter
    api.addFiles(
        '.npm/package/node_modules/react-router/dist/react-router.js', 'client'
    );

    api.addFiles([
        "lib/date.js",
        "lib/URI.js",
        "j.coffee",
        "util.coffee",
        "dependency.coffee",
        "autovar.coffee",
        "dict.coffee",
        "list.coffee",
        "autodict.coffee",
        "autolist.coffee",
        "proptypes.coffee",
        "models.coffee",
        "components.coffee",
        "routing.coffee"
    ]);

    api.addFiles([
        "publish.coffee"
    ], "server");

    api.addFiles([
        "fetching.coffee"
    ], "client");

    api.export("J");
    api.export("$$");
});

Package.onTest(function(api) {
    api.use([
        "insecure",
        "tinytest",
        "coffeescript",
        "tracker",
        "jframework"
    ]);

    api.imply([
        "tracker",
        "reactive-var",
        "tinytest",
        "jframework"
    ]);

    api.addFiles([
        "tests/test-models.coffee",
        "tests/jframework-tests.coffee",
        "tests/publish-tests.coffee"
    ]);

    api.addFiles([
        "tests/jframework-client-tests.coffee"
    ], "client");
});