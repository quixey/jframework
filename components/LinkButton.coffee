J.dc 'LinkButton',
    props:
        style:
            default: {}
        onClick:
            type: React.PropTypes.func

    render: ->
        $$ ('span'),
            style:
                _.extend(
                    cursor: 'pointer'
                    color: 'blue'
                ,
                    @prop.style().toObj()
                )
            onClick: (e) => @prop.onClick()? e
            (@prop.children())