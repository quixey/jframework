J.dc 'CancelButton',
    props:
        onClick:
            type: React.PropTypes.func

    render: ->
        $$ ('LinkButton'),
            onClick: @prop.onClick()
            $$ ('span'),
                style:
                    fontSize: 12
                    color: '#999'
                ("Cancel")