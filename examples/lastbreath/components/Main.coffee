J.dc 'Main',
    mixins: [J.Routable]

    render: ->
        $$ ('div'),
            style:
                fontFamily: 'helvetica neue'
            $$ (ReactRouter.RouteHandler)