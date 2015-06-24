# Copyright 2015, Quixey Inc.
# All rights reserved.
#
# Licensed under the Modified BSD License found in the
# LICENSE file in the root directory of this source tree.


J.dc 'Expandable',
    props:
        heading:
            type: $$.element
        contractedChildren:
            type: $$.bool
            default: true
        expanded:
            type: $$.bool
        initialExpanded:
            type: $$.bool
            default: false
        iconSize:
            default: 14
        iconStyle:
            type: $$.style
            default: {}
        onChange:
            type: $$.func
        style:
            type: $$.style
            default: {}

    state:
        localExpanded:
            type: $$.bool
            default: -> @prop.initialExpanded()
            onChange: (__, localExpanded) ->
                if not @prop.expanded()?
                    @prop.onChange()? expanded: localExpanded

    reactives:
        expanded:
            val: ->
                @prop.expanded() ? @localExpanded()

    render: ->
        handleChangeEvent = (newExpanded) =>
            if @prop.expanded()?
                # Controlled Component mode
                @prop.onChange()? expanded: newExpanded
            else
                @localExpanded newExpanded
            null

        $$ ('div'),
            style: @prop.style().toObj()
            onClick:
                if not @expanded()
                    (e) => handleChangeEvent true

            $$ ('TableRow'),
                style:
                    width: '100%'

                $$ ('td'),
                    style:
                        _.extend(
                            verticalAlign: 'top'
                            width: 18
                            paddingRight: 4
                            cursor: 'pointer'
                            @prop.iconStyle().toObj()
                        )
                    onClick:
                        if @expanded()
                            (e) => handleChangeEvent false

                    $$ ('img'),
                        src: "/images/#{if @expanded() then 'expanded.png' else 'contracted.png'}"
                        style:
                            maxHeight: @prop.iconSize()
                            maxWidth: @prop.iconSize()

                $$ ('td'),
                    style:
                        verticalAlign: 'top'

                    if @prop.heading()?
                        $$ ('div'),
                            style:
                                cursor: 'pointer'
                            onClick:
                                if @expanded()
                                    (e) => handleChangeEvent false

                            (@prop.heading())

                            if not @expanded()
                                (@prop.contractedChildren())

                    if @expanded()
                        (@prop.children())
