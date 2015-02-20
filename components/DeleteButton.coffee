J.dc 'DeleteButton',
    props:
        onClick:
            type: React.PropTypes.func

    render: ->
        $$ ('LinkButton'),
            onClick: @prop.onClick()
            $$ ('span'),
                style:
                    fontSize: 12
                    color: 'red'
                    opacity: .5
                ("Delete")