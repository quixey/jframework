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
    instanceOfModel: (modelName) ->
        # XXX This doesn't currently work.

        # Here at definition time, J.Models[modelName]
        # probably hasn't been created yet. So we'll
        # just wait until validator call time.
        validator = ->
            # Okay, it's validator call time.
            modelClass = J.models[modelName]
            unless modelClass?
                throw new Meteor.Error "Invalid modelName #{JSON.stringify modelName} in instanceOfModel"

            React.PropTypes.instanceOf(modelClass).apply @, arguments

        validator.isRequired = ->
            # Okay, it's validator call time.
            modelClass = J.models[modelName]
            unless modelClass?
                throw new Meteor.Error "Invalid modelName #{JSON.stringify modelName} in instanceOfModel"

            React.PropTypes.instanceOf(modelClass).isRequired.apply @, arguments

        validator

    # J.PropTypes.key is a pseudo-propType that the
    # _id fieldSpec can use to declare that it isn't
    # part of the Normalized Kernel of our data model, i.e.
    # the model's key() instance function computed it
    # from other fields at db-insert time.
    key: {}

    number: {}

    object: {}

    string: {}


for propTypeName, propTypeFunc of J.PropTypes
    $$[propTypeName] = propTypeFunc