require 'objc_ext'
require 'irb_ext'
require 'node'

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

      @codeBlockRows = []
      @sourceBuffer = IRB::Source.new

      setupIRBForObject(object, binding: binding)

      self
    end
  end
  
  def loadView
    NSUserDefaults.standardUserDefaults.registerDefaults('WebKitDeveloperExtras' => true)
    
    @webView = WebView.alloc.init
    @webView.frameLoadDelegate = self
    @webView.setUIDelegate(self)

    resourcePath = File.dirname(__FILE__)
    path = File.join(resourcePath, 'inspector.html')
    @webView.mainFrame.loadHTMLString(File.read(path), baseURL: NSURL.fileURLWithPath(resourcePath))

    self.view = @webView
  end

  # actions

  def webView(webView, contextMenuItemsForElement: element, defaultMenuItems: defaultItems)
    fullScreenLabel = @splitView.isInFullScreenMode ? "Exit Full Screen" : "Enter Full Screen"
    menuItems = [
      NSMenuItem.alloc.initWithTitle("Clear console", action: "clearConsole:", keyEquivalent: ""),
      NSMenuItem.separatorItem,
      NSMenuItem.alloc.initWithTitle(fullScreenLabel, action: "toggleFullScreenMode:", keyEquivalent: ""),
      NSMenuItem.alloc.initWithTitle("Zoom In", action: "makeTextLarger:", keyEquivalent: ""),
      NSMenuItem.alloc.initWithTitle("Zoom Out", action: "makeTextSmaller:", keyEquivalent: ""),
    ]
    menuItems.each { |i| i.target = self }
    menuItems
  end

  def clearConsole(sender)
    @console.innerHTML = ''
    @expandableRowToNodeMap = {}
    @context.clear_buffer
    makeInputFieldPromptForInput(false)
  end

  def makeTextLarger(sender)
    @webView.makeTextLarger(sender)
  end

  def makeTextSmaller(sender)
    @webView.makeTextSmaller(sender)
  end

  def toggleFullScreenMode(sender)
    if @splitView.isInFullScreenMode
      @splitView.exitFullScreenModeWithOptions({})
    else
      @splitView.enterFullScreenMode(NSScreen.mainScreen, withOptions: {})
    end
    makeInputFieldPromptForInput(false)
  end

  # WebView related methods

  def webView(webView, didFinishLoadForFrame: frame)
    @webViewDataSource = webView.mainFrame.dataSource
    @document = webView.mainFrame.DOMDocument
    @bottomDiv = @document.getElementById('bottom')
    @console = @document.getElementById('console')
    @console.send("addEventListener:::", 'click', self, false)

    @inputField = @document.getElementById('inputField')
    @inputField.send("addEventListener:::", "keypress", self, false)
    @inputRow = @document.getElementById('inputRow')
    @inputPrompt = @document.getElementById('inputPrompt')

    makeInputFieldPromptForInput
  end

  def scrollWebViewToBottom
    @bottomDiv.scrollIntoView(true)
  end

  def handleEvent(event)
    element = event.target
    case element
    when DOMHTMLInputElement
      handleKeyEvent(event)
    when DOMHTMLTableCellElement
      toggleExpandableNode(element) if element.hasClassName?('expandable')
    when DOMHTMLAnchorElement
      newContextWithObjectOfNode(element)
    end
  end

  def handleKeyEvent(event)
    input = @inputField.value + event.keyCode.chr
    #p input
    #@sourceBuffer ||= IRB::Source.new(@context.source.buffer.dup)
    #@sourceBuffer << input
    #p @sourceBuffer.to_s
    #p source.syntax_error?
    #p source.code_block?
    
    source = IRB::Source.new(@sourceBuffer.buffer.dup)
    source << input
    #p source.to_s

    if event.keyCode == 13
      currentLine = @context.line + @sourceBuffer.buffer.size
      @inputPrompt.innerText = (currentLine + 1).to_s
      node = BasicNode.alloc.initWithPrefix(currentLine.to_s, value: input.htmlEscapeEntities)
      row = addConsoleNode(node)
      @codeBlockRows << row

      if source.code_block?
        #puts "code block!"
        processInput(source.buffer)
        removeCodeBlockStatusClasses
        @sourceBuffer = IRB::Source.new
        @codeBlockRows = []
      else
        puts "not a code block!"
        # not done yet
        @sourceBuffer = source
        setCodeBlockStatusClasses(source.code_block?)
        makeInputFieldPromptForInput
      end
    else
      setCodeBlockStatusClasses(source.code_block?)
    end
  end

  def removeCodeBlockStatusClasses
    @codeBlockRows.each { |r| r.className = '' }
    @inputField.className = ''
  end

  def setCodeBlockStatusClasses(complete)
    if @codeBlockRows.empty?
      if complete
        @inputRow.className = "code-block start end"
      else
        @inputRow.className = "code-block start end incomplete"
      end
    else
      if complete
        @codeBlockRows.first.className = "code-block start"
        @codeBlockRows[1..-1].each { |r| r.className = "code-block" }
        @inputRow.className = "code-block end"
      else
        @codeBlockRows.first.className = "code-block start incomplete"
        @codeBlockRows[1..-1].each { |r| r.className = "code-block incomplete" }
        @inputRow.className = "code-block end incomplete"
      end
    end
  end

  def toggleExpandableNode(prefix)
    row   = prefix.parentNode
    value = row.lastChild
    if prefix.hasClassName?('not-expanded')
      # if there is a table, show it, otherwise create and add one
      if (table = value.lastChild) && table.is_a?(DOMHTMLTableElement)
        table.show!
      else
        value.appendChild(childrenTableForNode(row['id'].to_i))
      end
      prefix.replaceClassName('not-expanded', 'expanded')
    else
      prefix.replaceClassName('expanded', 'not-expanded')
      value.lastChild.hide!
    end
  end

  def newContextWithObjectOfNode(anchor)
    row = anchor.parentNode.parentNode
    object_id = row['id'].to_i
    object = @expandableRowToNodeMap[object_id].object
    irb(object)
  end

  # DOM element related methods

  def addNode(node, toElement: element)
    @expandableRowToNodeMap[node.id] = node if node.expandable?
    row = rowForNode(node)
    element.appendChild(row)
    row
  end

  def addConsoleNode(node)
    addNode(node, toElement: @console)
  end

  def childrenTableForNode(id)
    node = @expandableRowToNodeMap[id]
    table = @document.createElement('table')
    node.children.each { |childNode| addNode(childNode, toElement: table) }
    table
  end

  def rowForNode(node)
    row    = @document.createElement("tr")
    prefix = @document.createElement("td")
    value  = @document.createElement("td")

    row['id']        = node.id
    prefix.className = "prefix#{' expandable not-expanded' if node.expandable?}"
    value.className  = "value"
    prefix.innerHTML = node.prefix
    if node.is_a?(NSImageNode)
      value.appendChild(imageElementForNode(node))
    else
      value.innerHTML = node.value
    end

    row.appendChild(prefix)
    row.appendChild(value)
    row
  end

  # Adds the image data as a WebResource to the webview's data source and
  # returns a IMG element, referencing the image.
  def imageElementForNode(node)
    image = node.object
    url = "NSImage://#{image.object_id}.jpg"

    @webViewDataSource.addSubresource(WebResource.alloc.initWithData(image.JFIFData(0.75),
                                                                URL: NSURL.URLWithString(url),
                                                           MIMEType: "image/jpeg",
                                                   textEncodingName: nil,
                                                          frameName: nil))

    element = @document.createElement('img')
    element['src'] = url
    element
  end

  # input/output related methods

  def makeInputFieldPromptForInput(clear = true)
    #@inputField.stringValue = '' if clear
    #@inputField.enabled = true
    #view.window.makeFirstResponder(@inputField)

    @inputField.value = '' if clear
    @inputField.focus
  end

  def processInput(lines)
    #p lines
    #lines.each { |line| addToHistory(line) }
    @thread[:inputLines] = lines.dup
    @thread.run
  end

  def addToHistory(line)
    @history << line
    @currentHistoryIndex = @history.size
  end

  def receivedResult(result)
    p result
    addConsoleNode(ObjectNode.nodeForObject(result))
    @delegate.receivedResult(self)

    makeInputFieldPromptForInput
    scrollWebViewToBottom
  end

  def receivedOutput(output)
    addConsoleNode(BasicNode.alloc.initWithValue(output.htmlEscapeEntities))
  end

  def receivedException(exception)
    string = IRB.formatter.exception(exception)
    addConsoleNode(BasicNode.alloc.initWithValue(string))
    makeInputFieldPromptForInput
    scrollWebViewToBottom
  end

  def terminate
    @delegate.send(:irbViewControllerTerminated, self)
  end

  # delegate methods of the input cell

  def control(control, textView: textView, completions: completions, forPartialWordRange: range, indexOfSelectedItem: item)
    @completion.call(textView.string).map { |s| s[range.location..-1] }
  end
  
  def control(control, textView: textView, doCommandBySelector: selector)
    #p selector
    case selector
    when :"cancelOperation:"
      toggleFullScreenMode(nil) if @splitView.isInFullScreenMode
    when :"insertTab:"
      textView.complete(self)
    when :"moveUp:"
      if @currentHistoryIndex > 0
        @currentHistoryIndex -= 1
        textView.string = @history[@currentHistoryIndex]
      else
        NSBeep()
      end
    when :"moveDown:"
      if @currentHistoryIndex < @history.size
        @currentHistoryIndex += 1
        line = @history[@currentHistoryIndex]
        textView.string = line ? line : ''
      else
        NSBeep()
      end
    else
      return false
    end
    true
  end

  private

  def setupIRBForObject(object, binding: binding)
    @context = IRB::Cocoa::Context.new(self, object, binding)
    @output = IRB::Cocoa::Output.new(self)
    @completion = IRB::Completion.new(@context)
    
    Thread.abort_on_exception = true
    
    @thread = Thread.new(self, @context) do |controller, context|
      IRB::Driver.current = controller
      Thread.stop # stop now, there's no input yet
      
      loop do
        if lines = Thread.current[:inputLines]
          Thread.current[:inputLines] = nil
          lines.each do |line|
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
