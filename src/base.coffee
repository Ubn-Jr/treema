class TreemaNode
  # Abstract node class

  # constructor defined
  schema: {}
  $el: null
  data: null
  options: null
  parent: null

  # templates
  nodeTemplate: '<div class="treema-row"><div class="treema-value"></div></div>'
  childrenTemplate: '<div class="treema-children"></div>'
  addChildTemplate: '<div class="treema-add-child" tabindex="9009">+</div>'
  tempErrorTemplate: '<span class="treema-temp-error"></span>'
  toggleTemplate: '<span class="treema-toggle-hit-area"><span class="treema-toggle"></span></span>'
  keyTemplate: '<span class="treema-key"></span>'
  errorTemplate: '<div class="treema-error"></div>'
  newPropertyTemplate: '<input class="treema-new-prop" />'

# behavior settings (overridden by subclasses)
  collection: false      # acts like an array or object
  ordered: false         # acts like an array
  keyed: false           # acts like an object
  editable: true         # can be changed
  directlyEditable: true # can be changed at this level directly
  skipTab: false         # is skipped over when tabbing between elements for editing
  valueClass: null

  # dynamically managed properties
  keyForParent: null
  childrenTreemas: null
  justCreated: true
  removed: false
  workingSchema: null

  # Thin interface for tv4 ----------------------------------------------------
  isValid: ->
    errors = @getErrors()
    return errors.length is 0

  getErrors: ->
    return [] unless @tv4
    if @isRoot()
      return @cachedErrors if @cachedErrors
      @cachedErrors = @tv4.validateMultiple(@data, @schema)['errors'] if @isRoot()
      return @cachedErrors
    root = @getRoot()
    errors = root.getErrors()
    my_path = @getPath()
    errors = (e for e in errors when e.dataPath[..my_path.length] is my_path)
    e.dataPath = e.dataPath[..my_path.length] for e in errors
    
    if @workingSchema
      moreErrors = @tv4.validateMultiple(@data, @workingSchema).errors
      errors = errors.concat(moreErrors)

    errors

  setUpValidator: ->
    if not @parent
      @tv4 = window['tv4']?.freshApi()
      @tv4.addSchema('#', @schema)
      @tv4.addSchema(@schema.id, @schema) if @schema.id
    else
      root = @getRoot()
      @tv4 = root.tv4

  # Abstract functions --------------------------------------------------------
  saveChanges: -> console.error('"saveChanges" has not been overridden.')
  getDefaultValue: -> null
  buildValueForDisplay: -> console.error('"buildValueForDisplay" has not been overridden.')
  buildValueForEditing: ->
    return unless @editable
    console.error('"buildValueForEditing" has not been overridden.')

  # collection specific
  getChildren: -> console.error('"getChildren" has not been overridden.') # should return a list of key-value-schema tuples
  getChildSchema: -> console.error('"getChildSchema" has not been overridden.')
  canAddChild: -> @collection and @editable and not @settings.preventEditing  # preventEditing does yet get passed to children
  canAddProperty: -> true
  addingNewProperty: -> false
  addNewChild: -> false

  # Subclass helper functions -------------------------------------------------
  buildValueForDisplaySimply: (valEl, text) ->
    text = text.slice(0,200) + '...' if text.length > 200
    valEl.append($("<div></div>").addClass('treema-shortened').text(text))

  buildValueForEditingSimply: (valEl, value, inputType=null) ->
    input = $('<input />')
    input.attr('type', inputType) if inputType
    input.val(value) unless value is null
    valEl.append(input)
    input.focus().select()
    input.blur @onEditInputBlur
    input

  onEditInputBlur: =>
    shouldRemove = @shouldTryToRemoveFromParent()
    @markAsChanged()
    @saveChanges(@getValEl())
    input = @getValEl().find('input, textarea, select')
    if @isValid() then @display() if @isEditing() else input.focus().select()
    if shouldRemove then @remove() else @flushChanges()
    @broadcastChanges()

  shouldTryToRemoveFromParent: ->
    val = @getValEl()
    return if val.find('select').length
    inputs = val.find('input, textarea')
    for input in inputs
      input = $(input)
      return false if input.attr('type') is 'checkbox' or input.val()
    return true

  limitChoices: (options) ->
    @enum = options
    @buildValueForEditing = (valEl) =>
      input = $('<select></select>')
      input.append($('<option></option>').text(option)) for option in @enum
      index = @enum.indexOf(@data)
      input.prop('selectedIndex', index) if index >= 0
      valEl.append(input)
      input.focus()
      input.blur @onEditInputBlur
      input

    @saveChanges = (valEl) =>
      index = valEl.find('select').prop('selectedIndex')
      @data = @enum[index]
      TreemaNode.changedTreemas.push(@)
      @broadcastChanges()

  # Initialization ------------------------------------------------------------
  @pluginName = "treema"
  defaults =
    schema: {}
    callbacks: {}

  constructor: (@$el, options, @parent) ->
    @$el = @$el or $('<div></div>')
    @settings = $.extend {}, defaults, options
    @schema = @settings.schema
    @data = options.data
    @patches = []
    @callbacks = @settings.callbacks
    @_defaults = defaults
    @_name = TreemaNode.pluginName
    @setUpValidator()
    @populateData()
    @previousState = @copyData()

  build: ->
    @$el.addClass('treema-node').addClass('treema-clearfix')
    @$el.empty().append($(@nodeTemplate))
    @$el.data('instance', @)
    @$el.addClass('treema-root') unless @parent
    @$el.attr('tabindex', 9001) unless @parent
    @justCreated = false unless @parent
    @$el.append($(@childrenTemplate)).addClass('treema-closed') if @collection
    valEl = @getValEl()
    valEl.addClass(@valueClass) if @valueClass
    valEl.addClass('treema-display') if @directlyEditable
    @buildValueForDisplay(valEl)
    @open() if @collection and not @parent
    @setUpGlobalEvents() unless @parent
    @setUpLocalEvents() if @parent
    @updateMyAddButton() if @collection
    @createSchemaSelector() if @workingSchemas?.length > 1
    @createTypeSelector() if @getTypes().length > 1
    schema = @workingSchema or @schema
    @limitChoices(schema.enum) if schema.enum
    @$el

  populateData: ->
    @data = @data or @schema.default or @getDefaultValue()
    
  setWorkingSchema: (@workingSchema, @workingSchemas) ->
    
  createSchemaSelector: ->
    select = $('<select></select>').addClass('treema-schema-select')
    for schema, i in @workingSchemas
      label = @makeWorkingSchemaLabel(schema)
      option = $('<option></option>').attr('value', i).text(label)
      option.attr('selected', true) if schema is @workingSchema
      select.append(option)
    select.change(@onSelectSchema)
    @$el.find('> .treema-row').prepend(select)
    
  makeWorkingSchemaLabel: (schema) ->
    return schema.title if schema.title?
    return schema.type if schema.type?
    return '???'

  getTypes: ->
    schema = @workingSchema or @schema
    types = schema.type or [ "string", "number", "integer", "boolean", "null", "array", "object" ]
    types = [types] unless $.isArray(types)
    types
    
  createTypeSelector: ->
    div = $('<div></div>').addClass('treema-type-select-container')
    select = $('<select></select>').addClass('treema-type-select')
    button = $('<button></button>').addClass('treema-type-select-button')
    currentType = $.type(@data)
    currentType = 'integer' if currentType == 'number' and @data % 1 is 0
    for type in @getTypes()
      option = $('<option></option>').attr('value', type).text(type)
      if type is currentType
        option.attr('selected', true)
        button.text(@typeToLetter(type))
      select.append(option)
    div.append(button)
    div.append(select)
    select.change(@onSelectType)
    @$el.find('> .treema-row').prepend(div)
    
  typeToLetter: (type) ->
    return {
      'boolean': 'B'
      'array': 'A'
      'object': 'O'
      'string': 'S'
      'number': 'F'
      'integer': 'I'
      'null': 'N'
    }[type]

  # Event handling ------------------------------------------------------------
  setUpGlobalEvents: ->
    @$el.dblclick (e) => $(e.target).closest('.treema-node').data('instance')?.onDoubleClick(e)

    @$el.click (e) =>
      $(e.target).closest('.treema-node').data('instance')?.onClick(e)
      @broadcastChanges(e)

    @$el.keydown (e) =>
      $(e.target).closest('.treema-node').data('instance')?.onKeyDown(e)
      @broadcastChanges(e)

  broadcastChanges: (e) ->
    if @callbacks.select and TreemaNode.didSelect
      TreemaNode.didSelect = false
      @callbacks.select(e, @getSelectedTreemas())
    if TreemaNode.changedTreemas.length
      changes = (t for t in TreemaNode.changedTreemas when not t.removed)
      @callbacks.change?(e, jQuery.unique(changes))
      TreemaNode.changedTreemas = []

  markAsChanged: ->
    TreemaNode.changedTreemas.push(@)

  setUpLocalEvents: ->
    row = @$el.find('> .treema-row')
    row.mouseenter @onMouseEnter if @callbacks.mouseenter?
    row.mouseleave @onMouseLeave if @callbacks.mouseleave?

  onMouseEnter: (e) => @callbacks.mouseenter(e, @)
  onMouseLeave: (e) => @callbacks.mouseleave(e, @)

  onClick: (e) ->
    return if e.target.nodeName in ['INPUT', 'TEXTAREA']
    clickedValue = $(e.target).closest('.treema-value').length  # Clicks are in children of .treema-value nodes
    clickedToggle = $(e.target).hasClass('treema-toggle') or $(e.target).hasClass('treema-toggle-hit-area')
    usedModKey = e.shiftKey or e.ctrlKey or e.metaKey
    @keepFocus() unless clickedValue and not @collection
    return @toggleEdit() if @isDisplaying() and clickedValue and @canEdit() and not usedModKey
    if not usedModKey and (clickedToggle or (clickedValue and @collection))
      if not clickedToggle
        @deselectAll()
        @select()
      return @toggleOpen()
    return @addNewChild() if $(e.target).closest('.treema-add-child').length and @collection
    return if @isRoot() or @isEditing()
    return @shiftSelect() if e.shiftKey
    return @toggleSelect() if e.ctrlKey or e.metaKey
    return @select()

  onDoubleClick: (e) ->
    return unless @collection
    clickedKey = $(e.target).hasClass('treema-key')
    return unless clickedKey
    @open() if @isClosed()
    @addNewChild()

  onKeyDown: (e) ->
    @onEscapePressed(e) if e.which is 27
    @onTabPressed(e) if e.which is 9
    @onLeftArrowPressed(e) if e.which is 37
    @onUpArrowPressed(e) if e.which is 38
    @onRightArrowPressed(e) if e.which is 39
    @onDownArrowPressed(e) if e.which is 40
    @onEnterPressed(e) if e.which is 13
    @onNPressed(e) if e.which is 78
    @onSpacePressed(e) if e.which is 32
    @onTPressed(e) if e.which is 84
    @onFPressed(e) if e.which is 70
    @onDeletePressed(e) if e.which is 8

  # Default keyboard behaviors ------------------------------------------------

  onLeftArrowPressed: (e) ->
    return if @inputFocused()
    @navigateOut()
    e.preventDefault()

  onRightArrowPressed: (e) ->
    return if @inputFocused()
    @navigateIn()
    e.preventDefault()

  onUpArrowPressed: (e) ->
    return if @inputFocused()
    @navigateSelection(-1)
    e.preventDefault()

  onDownArrowPressed: (e) ->
    return if @inputFocused()
    @navigateSelection(1)
    e.preventDefault()
  
  inputFocused: ->
    return true if document.activeElement.nodeName in ['INPUT', 'TEXTAREA']

  onSpacePressed: ->
  onTPressed: ->
  onFPressed: ->

  onDeletePressed: (e) ->
    if @editingIsHappening() and not $(e.target).val()
      @display()
      @select()
      @removeSelectedNodes()
      e.preventDefault()
    return if e.target.nodeName in ['INPUT', 'TEXTAREA']
    e.preventDefault()
    @removeSelectedNodes()

  onEscapePressed: ->
    return unless @isEditing()
    return @remove() if @justCreated
    @display() if @isEditing()
    @select() unless @isRoot()
    @getRootEl().focus()

  onEnterPressed: (e) ->
    offset = if e.shiftKey then -1 else 1
    return @addNewChild() if offset is 1 and $(e.target).hasClass('treema-add-child')
    @traverseWhileEditing(offset, true)

  onTabPressed: (e) ->
    offset = if e.shiftKey then -1 else 1
    return if @hasMoreInputs(offset)
    e.preventDefault()
    @traverseWhileEditing(offset, false)

  hasMoreInputs: (offset) ->
    inputs = @getInputs().toArray()
    inputs = inputs.reverse() if offset < 0
    passedFocusedEl = false
    for input in inputs
      if input is document.activeElement
        passedFocusedEl = true
        continue
      continue unless passedFocusedEl
      return true
    return false

  onNPressed: (e) ->
    return if @editingIsHappening()
    selected = @getLastSelectedTreema()
    target = if selected?.collection then selected else selected?.parent
    return unless target
    success = target.addNewChild()
    @deselectAll() if success
    e.preventDefault()

  # Tree traversing/navigation ------------------------------------------------
  # (traversing means editing and adding fields, pressing enter and tab)
  # (navigation means selecting fields, pressing arrow keys)

  traverseWhileEditing: (offset, aggressive) ->
    shouldRemove = false
    selected = @getLastSelectedTreema()
    editing = @isEditing()
    return selected.edit() if not editing and selected?.canEdit()

    if editing
      shouldRemove = @shouldTryToRemoveFromParent()
      @saveChanges(@getValEl())
      @flushChanges() unless shouldRemove
      unless aggressive or @isValid()
        @refreshErrors() # make sure workingSchema's errors come through
        return
      if shouldRemove and $(@$el[0].nextSibling)?.hasClass('treema-add-child') and offset is 1
        offset = 2
      @endExistingEdits()
      @select()

    ctx = @traversalContext(offset)
    return @getRoot().addChild() unless ctx
    if not ctx.origin
      targetEl = if offset > 0 then ctx.first else ctx.last
      @selectOrActivateElement(targetEl)

    selected = $(ctx.origin).data('instance')
    if offset > 0 and aggressive and selected.collection and selected.isClosed()
      return selected.open()

    targetEl = if offset > 0 then ctx.next else ctx.prev
    if not targetEl
      targetEl = if offset > 0 then ctx.first else ctx.last
    @selectOrActivateElement(targetEl)
    if shouldRemove then @remove() else @refreshErrors()

  selectOrActivateElement: (el) ->
    el = $(el)
    treema = el.data('instance')
    if treema
      return if treema.canEdit() then treema.edit() else treema.select()

    # otherwise it must be an 'add' element
    @deselectAll()
    el.focus()

  navigateSelection: (offset) ->
    ctx = @navigationContext()
    return unless ctx
    if not ctx.origin
      targetTreema = if offset > 0 then ctx.first else ctx.last
      return targetTreema.select()
    targetTreema = if offset > 0 then ctx.next else ctx.prev
    if not targetTreema
      targetTreema = if offset > 0 then ctx.first else ctx.last
    targetTreema?.select()

  navigateOut: ->
    selected = @getLastSelectedTreema()
    return if not selected
    return selected.close() if selected.isOpen()
    return if (not selected.parent) or selected.parent.isRoot()
    selected.parent.select()

  navigateIn: ->
    for treema in @getSelectedTreemas()
      continue unless treema.collection
      treema.open() if treema.isClosed()

  traversalContext: (offset) ->
    list = @getNavigableElements(offset)
    origin = @getLastSelectedTreema()?.$el[0]
    origin = @getRootEl().find('.treema-add-child:focus')[0] if not origin
    origin = @getRootEl().find('.treema-new-prop')[0] if not origin
    @wrapContext(list, origin, offset)

  navigationContext: ->
    list = @getVisibleTreemas()
    origin = @getLastSelectedTreema()
    @wrapContext(list, origin)

  wrapContext: (list, origin, offset=1) ->
    return unless list.length
    c =
      first: list[0]
      last: list[list.length-1]
      origin: origin
    if origin
      offset = Math.abs(offset)
      originIndex = list.indexOf(origin)
      c.next = list[originIndex+offset]
      c.prev = list[originIndex-offset]
    return c

  # Undo/redo -----------------------------------------------------------------

  # TODO: implement undo/redo, including saving and restoring which nodes are open

#  patches: []
#  patchIndex: 0
#  previousState: null
#
#  saveState: ->
#    @patches = @patches.slice(@patchIndex)
#    @patchIndex = 0
#    @patches.splice(0, 0, jsondiffpatch.diff(@previousState, @data))
#    @previousState = @copyData()
#    @patches = @patches[..10]
#
#  undo: ->
#    return unless @patches[@patchIndex]
#    jsondiffpatch.unpatch(@previousState, @patches[@patchIndex])


  # Editing values ------------------------------------------------------------
  canEdit: ->
    return false if @schema.readOnly
    return false if @settings.preventEditing  # preventEditing does not yet get passed to children
    return false if not @editable
    return false if not @directlyEditable
    return false if @collection and @isOpen()
    return true

  display: ->
    @toggleEdit('treema-display')

  edit: (options={}) ->
    @toggleEdit('treema-edit')
    @focusLastInput() if options.offset? and options.offset < 0

  toggleEdit: (toClass=null) ->
    return unless @editable
    valEl = @getValEl()
    return if toClass and valEl.hasClass(toClass)
    toClass = toClass or (if valEl.hasClass('treema-display') then 'treema-edit' else 'treema-display')
    @endExistingEdits() if toClass is 'treema-edit'
    valEl.removeClass('treema-display').removeClass('treema-edit').addClass(toClass)

    valEl.empty()
    @buildValueForDisplay(valEl) if @isDisplaying()

    if @isEditing()
      @buildValueForEditing(valEl)
      @deselectAll()

  endExistingEdits: ->
    editing = @getRootEl().find('.treema-edit').closest('.treema-node')
    for elem in editing
      treema = $(elem).data('instance')
      treema.saveChanges(treema.getValEl())
      treema.display()
      @markAsChanged()

  flushChanges: ->
    @parent.integrateChildTreema(@) if @parent and @justCreated
    @getRoot().cachedErrors = null
    @justCreated = false
    @markAsChanged()
    return @refreshErrors() unless @parent
    @parent.data[@keyForParent] = @data
    @parent.refreshErrors()
    @parent.buildValueForDisplay(@parent.getValEl().empty())

  focusLastInput: ->
    inputs = @getInputs()
    last = inputs[inputs.length-1]
    $(last).focus().select()

  # Removing nodes ------------------------------------------------------------
  removeSelectedNodes: ->
    selected = @getSelectedTreemas()
    toSelect = null
    if selected.length is 1
      nextSibling = selected[0].$el.next('.treema-node').data('instance')
      prevSibling = selected[0].$el.prev('.treema-node').data('instance')
      toSelect = nextSibling or prevSibling or selected[0].parent
    treema.remove() for treema in selected
    toSelect.select() if toSelect and not @getSelectedTreemas().length

  remove: ->
    required = @parent and @parent.schema.required? and @keyForParent in @parent.schema.required
    if required
      tempError = @createTemporaryError('required')
      @$el.prepend(tempError)
      return false

    root = @getRootEl()
    @$el.remove()
    @removed = true
    root.focus() if document.activeElement is $('body')[0]
    return true unless @parent?
    delete @parent.childrenTreemas[@keyForParent]
    delete @parent.data[@keyForParent]
    @parent.orderDataFromUI() if @parent.ordered
    @parent.refreshErrors()
    @parent.updateMyAddButton()
    @parent.markAsChanged()
    @parent.buildValueForDisplay(@parent.getValEl().empty())
    @broadcastChanges()
    return true

  # Opening/closing collections -----------------------------------------------
  toggleOpen: ->
    if @isClosed() then @open() else @close()
    @

  open: ->
    return unless @isClosed()
    childrenContainer = @$el.find('.treema-children').detach()
    childrenContainer.empty()
    @childrenTreemas = {}
    for [key, value, schema] in @getChildren()
      continue if schema.format is 'hidden'
      treema = TreemaNode.make(null, {schema: schema, data:value}, @, key)
      @integrateChildTreema(treema)
      childNode = @createChildNode(treema)
      childrenContainer.append(childNode)
    @$el.append(childrenContainer).removeClass('treema-closed').addClass('treema-open')
    childrenContainer.append($(@addChildTemplate))
    if @ordered and childrenContainer.sortable
      childrenContainer.sortable?(deactivate: @orderDataFromUI).disableSelection?()
    @refreshErrors()

  openDeep: (n) ->
    return unless (n ?= 9001)
    @open()
    child.openDeep(n - 1) for childIndex, child of @childrenTreemas ? {}

  orderDataFromUI: =>
    children = @$el.find('> .treema-children > .treema-node')
    index = 0
    @childrenTreemas = {}  # rebuild it
    @data = if $.isArray(@data) then [] else {}
    for child in children
      treema = $(child).data('instance')
      continue unless treema
      treema.keyForParent = index
      @childrenTreemas[index] = treema
      @data[index] = treema.data
      index += 1
    @flushChanges()

  close: ->
    return unless @isOpen()
    @data[key] = treema.data for key, treema of @childrenTreemas
    @$el.find('.treema-children').empty()
    @$el.addClass('treema-closed').removeClass('treema-open')
    @childrenTreemas = null
    @refreshErrors()
    @buildValueForDisplay(@getValEl().empty())

  # Selecting/deselecting nodes -----------------------------------------------
  select: ->
    numSelected = @getSelectedTreemas().length
    # if we have multiple selected, we want this row to be selected at the end
    excludeSelf = numSelected is 1
    @deselectAll(excludeSelf)
    @toggleSelect()
    @keepFocus()
    TreemaNode.didSelect = true

  deselectAll: (excludeSelf=false) ->
    for treema in @getSelectedTreemas()
      continue if excludeSelf and treema is @
      treema.$el.removeClass('treema-selected')
    @clearLastSelected()
    TreemaNode.didSelect = true

  toggleSelect: ->
    @clearLastSelected()
    @$el.toggleClass('treema-selected') unless @isRoot()
    @$el.addClass('treema-last-selected') if @isSelected()
    TreemaNode.didSelect = true

  clearLastSelected: ->
    @getRootEl().find('.treema-last-selected').removeClass('treema-last-selected')

  shiftSelect: ->
    lastSelected = @getRootEl().find('.treema-last-selected')
    @select() if not lastSelected.length
    @deselectAll()
    allNodes = @getRootEl().find('.treema-node')
    started = false
    for node in allNodes
      node = $(node).data('instance')
      if not started
        started = true if node is @ or node.wasSelectedLast()
        node.$el.addClass('treema-selected') if started
        continue
      break if started and (node is @ or node.wasSelectedLast())
      node.$el.addClass('treema-selected')
    @$el.addClass('treema-selected')
    lastSelected.addClass('treema-selected')
    lastSelected.removeClass('treema-last-selected')
    @$el.addClass('treema-last-selected')
    TreemaNode.didSelect = true

  # Working schemas -----------------------------------------------------------
  
  # Schemas can be flexible using combinatorial properties and references.
  # But it simplifies logic if schema props like $ref, allOf, anyOf, and oneOf 
  # are flattened into a list of more straightforward user choices.
  # These simplifications are called working schemas.

  buildWorkingSchemas: (originalSchema) ->
    baseSchema = @resolveReference($.extend(true, {}, originalSchema or {}))
    allOf = baseSchema.allOf
    anyOf = baseSchema.anyOf
    oneOf = baseSchema.oneOf
    delete baseSchema.allOf if baseSchema.allOf?
    delete baseSchema.anyOf if baseSchema.anyOf?
    delete baseSchema.oneOf if baseSchema.oneOf?

    if allOf?
      for schema in allOf
        $.extend(null, baseSchema, @resolveReference(schema))

    workingSchemas = []
    singularSchemas = []
    singularSchemas = singularSchemas.concat(anyOf) if anyOf?
    singularSchemas = singularSchemas.concat(oneOf) if oneOf?

    for singularSchema in singularSchemas
      singularSchema = @resolveReference(singularSchema)
      s = $.extend(true, {}, baseSchema)
      s = $.extend(true, s, singularSchema)
      workingSchemas.push(s)
    workingSchemas = [baseSchema] if workingSchemas.length is 0
    workingSchemas

  resolveReference: (schema) ->
    if schema.$ref? then @tv4.getSchema(schema.$ref) else schema

  chooseWorkingSchema: (workingSchemas, data) ->
    return workingSchemas[0] if workingSchemas.length is 1
    root = @getRoot()
    for schema in workingSchemas
      result = tv4.validateMultiple(data, schema, false, root.schema)
      return schema if result.valid
    return workingSchemas[0]

  onSelectSchema: (e) =>
    index = parseInt($(e.target).val())
    workingSchema = @workingSchemas[index]
    defaultType = "null"
    defaultType = $.type(workingSchema.default) if workingSchema.default?
    defaultType = workingSchema.type if workingSchema.type?
    defaultType = defaultType[0] if $.isArray(defaultType)
    NodeClass = TreemaNode.getNodeClassForSchema(workingSchema, defaultType)
    @workingSchema = workingSchema
    @replaceNode(NodeClass)

  onSelectType: (e) =>
    newType = $(e.target).val()
    NodeClass = TreemaNode.getNodeClassForSchema(@workingSchema, newType)
    @replaceNode(NodeClass)
    
  replaceNode: (NodeClass) ->
    settings = $.extend(true, {}, @settings)
    delete settings.data if settings.data
    newNode = new NodeClass(null, settings, @parent)
    newNode.data = newNode.getDefaultValue()
    newNode.data = @workingSchema.default if @workingSchema.default?
    newNode.tv4 = @tv4
    newNode.keyForParent = @keyForParent if @keyForParent?
    newNode.setWorkingSchema(@workingSchema, @workingSchemas)
    @parent.createChildNode(newNode)
    @$el.replaceWith(newNode.$el)
    newNode.flushChanges() # should integrate


  # Child node utilities ------------------------------------------------------
  integrateChildTreema: (treema) ->
    treema.justCreated = false # no longer in limbo
    @childrenTreemas[treema.keyForParent] = treema
    treema.populateData()
    @data[treema.keyForParent] = treema.data
    treema

  createChildNode: (treema) ->
    childNode = treema.build()
    row = childNode.find('.treema-row')
    if @collection and @keyed
      name = treema.schema.title or treema.keyForParent
      keyEl = $(@keyTemplate).text(name)
      keyEl.attr('title', treema.schema.description) if treema.schema.description
      row.prepend(' : ')
      required = @schema.required or []
      keyEl.text(keyEl.text()+'*') if treema.keyForParent in required
      row.prepend(keyEl)
    childNode.prepend($(@toggleTemplate)) if treema.collection
    childNode

  # Validation errors ---------------------------------------------------------
  refreshErrors: ->
    @clearErrors()
    @showErrors()

  showErrors: ->
    return if @justCreated
    errors = @getErrors()
    erroredTreemas = []
    myPath = @getPath()
    for error in errors
      path = error.dataPath[1..]
      path = if path then path.split('/') else []
      deepestTreema = @
      for subpath in path
        unless deepestTreema.childrenTreemas
          error.forChild = true
          break
        subpath = parseInt(subpath) if deepestTreema.ordered
        deepestTreema = deepestTreema.childrenTreemas[subpath]
        unless deepestTreema
          console.error('could not find treema down path', path, @)
          return
      deepestTreema._errors = [] unless deepestTreema._errors and deepestTreema in erroredTreemas
      deepestTreema._errors.push(error)
      erroredTreemas.push(deepestTreema)

    for treema in $.unique(erroredTreemas)
      childErrors = (e for e in treema._errors when e.forChild)
      ownErrors = (e for e in treema._errors when not e.forChild)
      messages = (e.message for e in ownErrors)
      if childErrors.length > 0
        message = "[#{childErrors.length}] error"
        message = message + 's' if childErrors.length > 1
        messages.push(message)

      treema.showError(messages.join('<br />'))

  showError: (message) ->
    @$el.prepend($(@errorTemplate))
    @$el.find('> .treema-error').html(message).show()
    @$el.addClass('treema-has-error')

  clearErrors: ->
    @$el.find('.treema-error').remove()
    @$el.find('.treema-has-error').removeClass('treema-has-error')
    @$el.removeClass('treema-has-error')

  createTemporaryError: (message, attachFunction=null) ->
    attachFunction = @$el.prepend unless attachFunction
    @clearTemporaryErrors()
    return $(@tempErrorTemplate).text(message).delay(3000).fadeOut(1000, -> $(@).remove())

  clearTemporaryErrors: -> @getRootEl().find('.treema-temp-error').remove()

  # Utilities -----------------------------------------------------------------

  getValEl: -> @$el.find('> .treema-row .treema-value')
  getRootEl: -> @$el.closest('.treema-root')
  getRoot: -> 
    node = @
    node = node.parent while node.parent?
    node
  getInputs: -> @getValEl().find('input, textarea')
  getSelectedTreemas: -> ($(el).data('instance') for el in @getRootEl().find('.treema-selected'))
  getLastSelectedTreema: -> @getRootEl().find('.treema-last-selected').data('instance')
  getAddButtonEl: -> @$el.find('> .treema-children > .treema-add-child')
  getVisibleTreemas: -> ($(el).data('instance') for el in @getRootEl().find('.treema-node'))
  getNavigableElements: ->
    @getRootEl().find('.treema-node, .treema-add-child:visible').toArray()
  getPath: ->
    pathPieces = []
    pointer = @
    while pointer and pointer.keyForParent?
      pathPieces.push(pointer.keyForParent+'')
      pointer = pointer.parent
    pathPieces.reverse()
    return '/' + pathPieces.join('/')

  isRoot: -> @$el.hasClass('treema-root')
  isEditing: -> @getValEl().hasClass('treema-edit')
  isDisplaying: -> @getValEl().hasClass('treema-display')
  isOpen: -> @$el.hasClass('treema-open')
  isClosed: -> @$el.hasClass('treema-closed')
  isSelected: -> @$el.hasClass('treema-selected')
  wasSelectedLast: -> @$el.hasClass('treema-last-selected')
  editingIsHappening: -> @getRootEl().find('.treema-edit').length
  rootSelected: -> $(document.activeElement).hasClass('treema-root')

  keepFocus: -> @getRootEl().focus()
  copyData: -> $.extend(null, {}, {'d': @data})['d']
  updateMyAddButton: ->
    @$el.removeClass('treema-full')
    @$el.addClass('treema-full') unless @canAddChild()

  @nodeMap: {}

  @setNodeSubclass: (key, NodeClass) -> @nodeMap[key] = NodeClass

  @getNodeClassForSchema: (schema, def='string') ->
    NodeClass = null
    NodeClass = @nodeMap[schema.format] if schema.format
    return NodeClass if NodeClass
    NodeClass = @nodeMap[schema.type or def]
    return NodeClass if NodeClass
    @nodeMap['any']

  @make: (element, options, parent, keyForParent) ->
    workingSchemas = []
    type = if options.data? then $.type(options.data) else 'string'
    type = 'integer' if type == 'number' and options.data % 1
    if parent
      workingSchemas = parent.buildWorkingSchemas(options.schema)
      workingSchema = parent.chooseWorkingSchema(workingSchemas, options.data)
      NodeClass = @getNodeClassForSchema(workingSchema, type)
    else
      NodeClass = @getNodeClassForSchema(options.schema, type)
    newNode = new NodeClass(element, options, parent)
    newNode.tv4 = parent.tv4 if parent?
    newNode.keyForParent = keyForParent if keyForParent?
    if parent
      newNode.setWorkingSchema(workingSchema, workingSchemas)
    newNode

  @extend: (child) ->
    # https://github.com/jashkenas/coffee-script/issues/2385
    ctor = ->
    ctor:: = @::
    child:: = new ctor()
    child::constructor = child
    child.__super__ = @::

    # provides easy access to the given method on super (must use call or apply)
    child::super = (method) -> @constructor.__super__[method]
    child

  @didSelect = false
  @changedTreemas = []
