#= require trix/observers/device_observer

{defer} = Trix.Helpers
{handleEvent, findClosestElementFromNode, findElementForContainerAtOffset} = Trix.DOM

class Trix.InputController
  pastedFileCount = 0

  @keyNames:
    "8": "backspace"
    "13": "return"
    "37": "left"
    "39": "right"
    "68": "d"
    "72": "h"
    "79": "o"

  constructor: (@element) ->
    @deviceObserver = new Trix.DeviceObserver @element
    @deviceObserver.delegate = this

    for event, handler of @events
      handleEvent event, onElement: @element, withCallback: handler.bind(this), inPhase: "capturing"

  # Device observer delegate

  deviceDidActivateVirtualKeyboard: ->
    @virtualKeyboardIsActive = true

  deviceDidDeactivateVirtualKeyboard: ->
    delete @virtualKeyboardIsActive

  # Input handlers

  events:
    keydown: (event) ->
      if keyName = @constructor.keyNames[event.keyCode]
        context = switch
          when event.ctrlKey then @keys.control
          when event.altKey then @keys.alt
          when event.shiftKey then @keys.shift
          else @keys

        context[keyName]?.call(this, event)

    keypress: (event) ->
      return if @virtualKeyboardIsActive
      return if (event.metaKey or event.ctrlKey) and not event.altKey

      if event.which is null
        character = String.fromCharCode event.keyCode
      else if event.which isnt 0 and event.charCode isnt 0
        character = String.fromCharCode event.charCode

      if character?
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString(character)

    dragenter: (event) ->
      event.preventDefault()

    dragstart: (event) ->
      target = event.target
      @draggedRange = @responder?.getLocationRange()

    dragover: (event) ->
      if @draggedRange or "Files" in event.dataTransfer?.types
        event.preventDefault()

    dragend: (event) ->
      delete @draggedRange

    drop: (event) ->
      event.preventDefault()
      point = [event.clientX, event.clientY]
      @responder?.setLocationRangeFromPoint(point)

      if @draggedRange
        @delegate?.inputControllerWillMoveText()
        @responder?.moveTextFromLocationRange(@draggedRange)
        delete @draggedRange

      else if files = event.dataTransfer.files
        @delegate?.inputControllerWillAttachFiles()
        for file in files
          if @responder?.insertFile(file)
            file.trixInserted = true

    cut: (event) ->
      @delegate?.inputControllerWillCutText()
      defer => @responder?.deleteBackward()

    paste: (event) ->
      paste = event.clipboardData ? event.testClipboardData
      return if "com.apple.webarchive" in paste.types
      event.preventDefault()

      if html = paste.getData("text/html")
        @delegate?.inputControllerWillPasteText()
        @responder?.insertHTML(html)
      else if string = paste.getData("text/plain")
        @delegate?.inputControllerWillPasteText()
        @responder?.insertString(string)

      if "Files" in paste.types
        if file = paste.items?[0]?.getAsFile?()
          if not file.name and extension = extensionForFile(file)
            file.name = "pasted-file-#{++pastedFileCount}.#{extension}"
          @delegate?.inputControllerWillAttachFiles()
          if @responder?.insertFile(file)
            file.trixInserted = true

    compositionstart: (event) ->
      @delegate?.inputControllerWillStartComposition?()
      @composing = true

    compositionend: (event) ->
      @delegate?.inputControllerWillEndComposition?()
      @composedString = event.data

    input: (event) ->
      if @composing and @composedString?
        @delegate?.inputControllerDidComposeCharacters?(@composedString) if @composedString
        delete @composedString
        delete @composing

  keys:
    backspace: (event) ->
      event.preventDefault()
      @delegate?.inputControllerWillPerformTyping()
      @responder?.deleteBackward()

    return: (event) ->
      event.preventDefault()
      @delegate?.inputControllerWillPerformTyping()
      @responder?.insertLineBreak()

    left: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.adjustPositionInDirection("backward")


    right: (event) ->
      if @selectionIsInCursorTarget()
        event.preventDefault()
        @responder?.adjustPositionInDirection("forward")

    control:
      d: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.deleteForward()

      h: (event) ->
        @delegate?.inputControllerWillPerformTyping()
        @backspace(event)

      o: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n", updatePosition: false)

    alt:
      backspace: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.deleteWordBackward()

    shift:
      return: (event) ->
        event.preventDefault()
        @delegate?.inputControllerWillPerformTyping()
        @responder?.insertString("\n")

      left: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandLocationRangeInDirection("backward")

      right: (event) ->
        if @selectionIsInCursorTarget()
          event.preventDefault()
          @responder?.expandLocationRangeInDirection("forward")

  selectionIsInCursorTarget: ->
    @responder?.selectionIsInCursorTarget()

  extensionForFile = (file) ->
    file.type?.match(/\/(\w+)$/)?[1]
