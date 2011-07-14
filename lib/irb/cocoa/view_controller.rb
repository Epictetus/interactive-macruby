require 'objc_ext'
require 'irb_ext'
require 'node'
require 'list_view'

class IRBViewController < NSViewController
  include IRB::Cocoa

  INPUT_FIELD_HEIGHT = 22

  attr_reader :output
  attr_reader :context

  def initWithObject(object, binding: binding, delegate: delegate)
    if init
      @delegate = delegate
      @history = []
      @currentHistoryIndex = 0
      @expandableRowToNodeMap = {}

      setupIRBForObject(object, binding: binding)

      self
    end
  end
  
  def loadView
    self.view = ScrollableListView.new
    @inputField = view.listView.inputField
    @inputField.delegate = self
    @inputField.target = self
    @inputField.action = "inputFromInputField:"
    setupContextualMenu
  end

  # actions

  def setupContextualMenu
    menu = NSMenu.new
    menu.addItemWithTitle("Clear console", action:"clearConsole:",         keyEquivalent: "k").target = self
    menu.addItem(NSMenuItem.separatorItem)
    menu.addItemWithTitle("",              action:"toggleFullScreenMode:", keyEquivalent: "F").target = self
    menu.addItemWithTitle("Zoom In",       action:"makeTextLarger:",       keyEquivalent: "+").target = view.listView
    menu.addItemWithTitle("Zoom Out",      action:"makeTextSmaller:",      keyEquivalent: "-").target = view.listView
    view.contentView.menu = menu
  end

  def validateUserInterfaceItem(item)
    if item.action == :'toggleFullScreenMode:'
      item.title = view.isInFullScreenMode ? "Exit Full Screen" : "Enter Full Screen"
    end
    true
  end

  def clearConsole(sender)
    view.listView.clear
    @expandableRowToNodeMap = {}
    @context.clear_buffer
    makeInputFieldPromptForInput(false)
  end

  def toggleFullScreenMode(sender)
    if view.isInFullScreenMode
      view.exitFullScreenModeWithOptions({})
    else
      view.enterFullScreenMode(NSScreen.mainScreen, withOptions: {})
    end
    makeInputFieldPromptForInput(false)
  end

  #def newContextWithObjectOfNode(anchor)
    #row = anchor.parentNode.parentNode
    #object_id = row['id'].to_i
    #object = @expandableRowToNodeMap[object_id].object
    #irb(object)
  #end

  def addNode(node, toListView:listView)
    @expandableRowToNodeMap[node.id] = node if node.expandable?
    listView.addNode(node)
  end

  def addConsoleNode(node)
    view.listView.inputFieldListItem.lineNumber = @context.line
    addNode(node, toListView:view.listView)
  end

  # input/output related methods

  def makeInputFieldPromptForInput(clear = true)
    @inputField.stringValue = '' if clear
    @inputField.enabled = true
    view.window.makeFirstResponder(@inputField)
  end

  def processInput(line)
    @sourceBuffer << line
    addToHistory(line)

    node = BasicNode.alloc.initWithPrefix(@context.line, value:line)
    addConsoleNode(node)
    makeInputFieldPromptForInput(true)

    if @sourceBuffer.code_block?
      @inputField.enabled = false
      @thread[:input] = @sourceBuffer.buffer
      @thread.run
      @sourceBuffer = IRB::Source.new
    end
  end

  def addToHistory(line)
    @history << line
    @currentHistoryIndex = @history.size
  end

  def receivedResult(result)
    addConsoleNode(ObjectNode.nodeForObject(result))
    @delegate.receivedResult(self)
    makeInputFieldPromptForInput
  end

  def receivedOutput(output)
    addConsoleNode(BasicNode.alloc.initWithValue(output))
  end

  def receivedException(exception)
    string = IRB.formatter.exception(exception)
    addConsoleNode(BasicNode.alloc.initWithValue(string))
    makeInputFieldPromptForInput
  end

  def terminate
    @delegate.send(:irbViewControllerTerminated, self)
  end

  # delegate methods of the input cell

  def control(control, textView:textView, completions:completions, forPartialWordRange:range, indexOfSelectedItem:item)
    @completion.call(textView.string).map { |s| s[range.location..-1] }
  end
  
  def control(control, textView: textView, doCommandBySelector: selector)
    #p selector
    case selector
    when :"insertNewline:"
      processInput(textView.string)
    when :"cancelOperation:"
      toggleFullScreenMode(nil) if view.isInFullScreenMode
    when :"insertTab:"
      textView.complete(self)
    when :"moveUp:"
      lineCount = textView.string.strip.split("\n").size
      if lineCount > 1
        return false
      else
        if @currentHistoryIndex > 0
          @currentHistoryIndex -= 1
          textView.string = @history[@currentHistoryIndex]
        else
          NSBeep()
        end
      end
    when :"moveDown:"
      lineCount = textView.string.strip.split("\n").size
      if lineCount > 1
        return false
      else
        if @currentHistoryIndex < @history.size
          @currentHistoryIndex += 1
          line = @history[@currentHistoryIndex]
          textView.string = line ? line : ''
        else
          NSBeep()
        end
      end
    else
      return false
    end
    true
  end

  private

  def setupIRBForObject(object, binding: binding)
    @context      = IRB::Cocoa::Context.new(self, object, binding)
    @output       = IRB::Cocoa::Output.new(self)
    @completion   = IRB::Completion.new(@context)
    @sourceBuffer = IRB::Source.new
    
    @thread = Thread.new(self, @context) do |controller, context|
      IRB::Driver.current = controller
      Thread.stop # stop now, there's no input yet
      
      loop do
        if input = Thread.current[:input]
          Thread.current[:input] = nil
          input.each do |line|
            unless context.process_line(line)
              controller.performSelectorOnMainThread("terminate",
                                          withObject: nil,
                                       waitUntilDone: false)
            end
          end
          Thread.stop # done processing, stop and await new input
        end
      end
    end
  end
end

module Kernel
  def irb(object, binding = nil)
    IRBWindowController.performSelectorOnMainThread("windowWithObjectAndBinding:",
                                                    withObject: [object, binding],
                                                    waitUntilDone: true)
    nil
  end
  
  private :irb
end
