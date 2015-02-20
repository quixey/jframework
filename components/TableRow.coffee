J.dc 'TableRow',
    props:
        style:
            type: React.PropTypes.object
            default: {}


    render: ->
        $$ ('table'),
            cellPadding: 0
            cellSpacing: 0
            style: @prop.style()
            $$ ('tbody'),
                {}
                $$ ('tr'),
                    {}
                    (@prop.children())