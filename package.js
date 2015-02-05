Package.describe({
    summary: "J Framework for Meteor + React",
    version: "0.0.1"
});

Npm.depends({
    "react-router": "0.11.6"
});

Package.onUse(function(api) {
    api.use("underscore");
    api.use("ordered-dict");
    api.use("coffeescript");
    api.use("tracker");
    api.use("reactive-var");
    api.use("quixey:react");

    api.imply("ordered-dict");
    api.imply("underscore");
    api.imply("quixey:react");

    // Sets up window.ReactRouter
    api.addFiles(
        '.npm/package/node_modules/react-router/dist/react-router.js', 'client'
    );

    api.addFiles([
        "lib/date.js",
        "lib/URI.js",
        "j.coffee",
        "util.coffee",
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

    api.export("J");
    api.export("$$");
});

Package.onTest(function(api) {
    api.use(["ordered-dict", "tinytest", "coffeescript", "tracker", "jframework"]);
    api.imply("ordered-dict");
    api.imply("tracker");
    api.imply("reactive-var");
    api.imply("tinytest");
    api.imply("jframework");
    api.addFiles("tests/jframework-tests.coffee");
    api.addFiles("tests/jframework-client-tests.coffee", "client");
});