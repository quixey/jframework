J.dc 'NotFound',
    mixins: [J.Routable],

    render: ->
        $$ ('div'),
            style:
                fontSize: 18
                fontWeight: 'bold'
            ('Not found.')