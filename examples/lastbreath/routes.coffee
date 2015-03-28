J.defineRouter ->
    $$ (ReactRouter.Route),
        handler: J.components.Main

        $$ (ReactRouter.DefaultRoute),
            handler: J.components.Home

        $$ (ReactRouter.NotFoundRoute),
            handler: J.components.NotFound