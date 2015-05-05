###
    Copyright 2015, Quixey Inc.
    All rights reserved.

    Licensed under the Modified BSD License found in the
    LICENSE file in the root directory of this source tree.
###

# NOTE:
# Using "_id: type: J.PropTypes.key" in a model definition is a useful feature
# that actually works right now.
# But all the other type stuff in J is not implemented at all, it's just
# a vague thought.


J.PropTypes =
    dict: {name: "J.PropTypes.dict"}

    elem: (componentSpec = null) ->
        # TODO

    func: {name: "J.PropTypes.func"}

    instance: (classSpec) ->
        if _.isString(classSpec)
            # Instance of a J.Model
            # FIXME: Doesn't work yet

            # Here at definition time, J.Models[modelName]
            # probably hasn't been created yet. So we'll
            # just wait until validator call time.
            validator = ->
                # Okay, it's validator call time.
                modelClass = J.models[modelName]
                unless modelClass?
                    throw new Meteor.Error "Invalid modelName #{JSON.stringify modelName} in instanceOfModel"

                $$.instance(modelClass).apply @, arguments

        else
            # Instance of an arbitrary JS class

    list: (params) ->
        ###
            Params:
                of:
                    A typeSpec to apply recursively to the elements of the list
        ###
        # TODO

    # J.PropTypes.key is a pseudo-propType that the
    # _id fieldSpec can use to declare that it isn't
    # part of the Normalized Kernel of our data model, i.e.
    # the model's key() instance function computed it
    # from other fields at db-insert time.
    key: {name: "J.PropTypes.key"}

    num: {name: "J.PropTypes.num"}

    or: (typeSpecs...) ->
        # TODO

    str: {name: "J.PropTypes.str"}


###
    Alias all PropTypes into $$
    E.g. $$.key, $$.func, $$.num
###
for propTypeName, propTypeFunc of J.PropTypes
    $$[propTypeName] = propTypeFunc