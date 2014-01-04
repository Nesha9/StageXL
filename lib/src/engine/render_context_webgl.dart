part of stagexl;

// TODO: Fix alpha issues (http://greggman.github.io/webgl-fundamentals/webgl/lessons/webgl-and-alpha.html)
// TODO: Handle WebGL context lost.
// TODO: Collect WebGL texture memory with reference counter?

class RenderContextWebGL extends RenderContext {

  CanvasElement _canvasElement;
  gl.RenderingContext _renderingContext;

  RenderTexture _renderTexture;
  RenderProgram _renderProgram;
  RenderProgram _renderProgramDefault;
  RenderProgram _renderProgramPrimitive;

  int _maskDepth = 0;

  RenderContextWebGL(CanvasElement canvasElement) : _canvasElement = canvasElement {

    _canvasElement.onWebGlContextLost.listen((e) => "ToDo: Handle WebGL context lost.");
    _canvasElement.onWebGlContextRestored.listen((e) => "ToDo: Handle WebGL context restored.");

    var renderingContext = _canvasElement.getContext3d(
        alpha: false, depth: false, stencil: true, antialias: true,
        premultipliedAlpha: false, preserveDrawingBuffer: false);

    if (renderingContext is! gl.RenderingContext) {
      throw new StateError("Failed to get WebGL context.");
    }

    _renderingContext = renderingContext;

    _renderingContext.enable(gl.BLEND);
    _renderingContext.disable(gl.STENCIL_TEST);
    _renderingContext.disable(gl.DEPTH_TEST);

    _renderingContext.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    _renderingContext.colorMask(true, true, true, true);
    _renderingContext.clearColor(1.0, 1.0, 1.0, 1.0);
    _renderingContext.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

    _renderProgramDefault = new RenderProgramDefault(this);
    _renderProgramPrimitive = new RenderProgramPrimitive(this);

    // ToDo: Replace "_updateViewPort". It's a strange mix between
    // setting the viewport and updating the program uniform.

    _activateRenderProgram(_renderProgramPrimitive);
    _updateViewPort();

    _activateRenderProgram(_renderProgramDefault);
    _updateViewPort();

    _renderTexture = null;
  }

  //-----------------------------------------------------------------------------------------------

  gl.RenderingContext get rawContext => _renderingContext;

  //-----------------------------------------------------------------------------------------------

  void clear() {
    _renderingContext.clearColor(1.0, 1.0, 1.0, 1.0);
    _renderingContext.clear(gl.COLOR_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
  }

  void renderQuad(RenderTextureQuad renderTextureQuad, Matrix matrix, num alpha) {

    var renderTexture = renderTextureQuad.renderTexture;

    if (identical(renderTexture, _renderTexture) == false) {
      var texture =  renderTexture.getTexture(this);
      _renderProgram.flush();
      _renderingContext.activeTexture(gl.TEXTURE0);
      _renderingContext.bindTexture(gl.TEXTURE_2D, texture);
      _renderTexture = renderTexture;
    }

    _renderProgram.renderQuad(renderTextureQuad, matrix, alpha);
  }

  void renderTriangle(num x1, num y1, num x2, num y2, num x3, num y3, Matrix matrix, int color) {
    _renderProgram.renderTriangle(x1, y1, x2, y2, x3, y3, matrix, color);
  }

  void flush() {
    _renderProgram.flush();
  }

  //-----------------------------------------------------------------------------------------------

  void beginRenderMask(RenderState renderState, Mask mask, Matrix matrix) {

    if (_maskDepth == 0) {
      _renderProgram.flush();
      _renderingContext.enable(gl.STENCIL_TEST);
    }

    _activateRenderProgram(_renderProgramPrimitive);

    _renderingContext.stencilFunc(gl.EQUAL, _maskDepth, 0xFF);
    _renderingContext.stencilOp(gl.KEEP, gl.KEEP, gl.INCR);
    _renderingContext.stencilMask(0xFF);
    _renderingContext.colorMask(false, false, false, false);
    _maskDepth += 1;

    mask._drawTriangles(this, matrix);

    _activateRenderProgram(_renderProgramDefault);

    _renderingContext.stencilFunc(gl.EQUAL, _maskDepth, 0xFF);
    _renderingContext.stencilMask(0x00);
    _renderingContext.colorMask(true, true, true, true);
  }

  void endRenderMask(Mask mask) {

    if (_maskDepth == 1) {

      _renderProgram.flush();
      _maskDepth = 0;
      _renderingContext.disable(gl.STENCIL_TEST);
      _renderingContext.clear(gl.STENCIL_BUFFER_BIT);

    } else {

      _activateRenderProgram(_renderProgramPrimitive);

      _renderingContext.stencilFunc(gl.EQUAL, _maskDepth, 0xFF);
      _renderingContext.stencilOp(gl.KEEP, gl.KEEP, gl.DECR);
      _renderingContext.stencilMask(0xFF);
      _renderingContext.colorMask(false, false, false, false);
      _maskDepth -= 1;

      var width = _renderingContext.drawingBufferWidth;
      var height = _renderingContext.drawingBufferHeight;
      var matrix = _identityMatrix;
      var color = Color.Magenta;

      _renderProgram.renderTriangle(0, 0, width, 0, width, height, matrix, color);
      _renderProgram.renderTriangle(0, 0, width, height, 0, height, matrix, color);

      _activateRenderProgram(_renderProgramDefault);

      _renderingContext.stencilFunc(gl.EQUAL, _maskDepth, 0xFF);
      _renderingContext.stencilMask(0x00);
      _renderingContext.colorMask(true, true, true, true);
    }
  }

  //-----------------------------------------------------------------------------------------------

  void beginRenderShadow(RenderState renderState, Shadow shadow, Matrix matrix) {

  }

  void endRenderShadow(Shadow shadow) {

  }

  //-----------------------------------------------------------------------------------------------

  _activateRenderProgram(RenderProgram renderProgram) {
    if (_renderProgram != null) {
      _renderProgram.flush();
    }
    _renderProgram = renderProgram;
    _renderProgram.activate();
  }

  _updateViewPort() {

    var width = _renderingContext.drawingBufferWidth;
    var height = _renderingContext.drawingBufferHeight;

    _renderingContext.viewport(0, 0, width, height);

    var program = _renderProgram.program;
    var viewTransformLocation = _renderingContext.getUniformLocation(program, "uViewMatrix");

    if (viewTransformLocation != null) {

      var viewMatrixList = new Float32List(9);
      viewMatrixList[0] = 2.0 / width;
      viewMatrixList[1] = 0.0;
      viewMatrixList[2] = 0.0;
      viewMatrixList[3] = 0.0;
      viewMatrixList[4] = - 2.0 / height;
      viewMatrixList[5] = 0.0;
      viewMatrixList[6] = -1.0;
      viewMatrixList[7] = 1.0;
      viewMatrixList[8] = 1.0;

      _renderingContext.uniformMatrix3fv(viewTransformLocation, false, viewMatrixList);
    }
  }


}