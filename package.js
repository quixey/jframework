Package.describe({
    summary: "J Framework for Meteor + React",
    version: "0.0.1"
});

Npm.depends({
    "react-router": "0.11.6"
});

Package.onUse(function(api) {
    api.use("underscore");
    api.use("coffeescript");
    api.use("quixey:react");

    // Sets up window.ReactRouter
    api.add_files(
        '.npm/package/node_modules/react-router/dist/react-router.js', 'client'
    );

    api.add_files([
        "lib/date.js",
        "lib/URI.js",
        "j.coffee",
        "util.coffee",
        "autovar.coffee",
        "dict.coffee",
        "autodict.coffee",
        "proptypes.coffee",
        "models.coffee",
        "components.coffee",
        "routing.coffee"
    ]);

    api.imply('quixey:react');
    api.export('J');
    api.export('$$');
});
