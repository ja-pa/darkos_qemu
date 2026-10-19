#include <SDL.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static GLuint shader(GLenum type, const char *source) {
    GLuint result = glCreateShader(type);
    GLint ok;
    glShaderSource(result, 1, &source, NULL);
    glCompileShader(result);
    glGetShaderiv(result, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char message[2048];
        glGetShaderInfoLog(result, sizeof(message), NULL, message);
        fprintf(stderr, "Shader compilation: %s\n", message);
        glDeleteShader(result);
        return 0;
    }
    return result;
}

int main(int argc, char **argv) {
    double seconds = 30;
    int result = 1;
    SDL_Window *window = NULL;
    SDL_GLContext context = NULL;
    GLuint vertex = 0, fragment = 0, program = 0, buffer = 0;
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc == 2 && strcmp(argv[1], "--drivers") == 0) {
        for (int i = 0; i < SDL_GetNumVideoDrivers(); ++i)
            puts(SDL_GetVideoDriver(i));
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "--seconds") == 0) {
        char *end;
        seconds = strtod(argv[2], &end);
        if (*end || seconds <= 0 || seconds > 3600) {
            fprintf(stderr, "Seconds must be greater than 0 and at most 3600\n");
            return 2;
        }
    } else if (argc != 1) {
        fprintf(stderr, "Usage: %s [--drivers | --seconds N]\n", argv[0]);
        return 2;
    }
    SDL_version version;
    SDL_GetVersion(&version);
    printf("SDL runtime: %u.%u.%u\n", version.major, version.minor, version.patch);
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) goto cleanup;
    const char *backend = SDL_GetCurrentVideoDriver();
    printf("SDL video backend: %s\n", backend ? backend : "none");
    if (!backend || SDL_strcasecmp(backend, "kmsdrm") != 0) {
        fprintf(stderr, "Expected kmsdrm; refusing another backend\n");
        goto cleanup;
    }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    window = SDL_CreateWindow("dArkOS SDL2 KMSDRM / GLES2", SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED, 640, 480,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN_DESKTOP);
    if (!window) goto cleanup;
    context = SDL_GL_CreateContext(window);
    if (!context) goto cleanup;
    printf("GL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\n",
           glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));
    SDL_GL_SetSwapInterval(1);
    vertex = shader(GL_VERTEX_SHADER,
        "attribute vec2 position; attribute vec3 color; varying vec3 c;"
        "uniform float phase; void main(){float s=sin(phase),t=cos(phase);"
        "gl_Position=vec4(mat2(t,-s,s,t)*position,0.,1.);c=color;}");
    fragment = shader(GL_FRAGMENT_SHADER,
        "precision mediump float; varying vec3 c; void main(){gl_FragColor=vec4(c,1.);}");
    if (!vertex || !fragment) goto cleanup;
    program = glCreateProgram();
    glAttachShader(program, vertex); glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glBindAttribLocation(program, 1, "color");
    glLinkProgram(program);
    GLint linked;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char message[2048];
        glGetProgramInfoLog(program, sizeof(message), NULL, message);
        fprintf(stderr, "Program link: %s\n", message);
        goto cleanup;
    }
    const GLfloat vertices[] = {0,.65f,1,0,0, -.65f,-.55f,0,1,0, .65f,-.55f,0,0,1};
    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5*sizeof(GLfloat), (void *)0);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5*sizeof(GLfloat), (void *)(2*sizeof(GLfloat)));
    glEnableVertexAttribArray(0); glEnableVertexAttribArray(1);
    glUseProgram(program);
    GLint phase = glGetUniformLocation(program, "phase");
    Uint64 start = SDL_GetPerformanceCounter(), frames = 0;
    double elapsed = 0;
    int running = 1;
    while (running && elapsed < seconds) {
        SDL_Event event;
        while (SDL_PollEvent(&event))
            if (event.type == SDL_QUIT || (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) running = 0;
        int width, height;
        SDL_GL_GetDrawableSize(window, &width, &height);
        glViewport(0, 0, width, height);
        glClearColor(.035f, .065f, .12f, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glUniform1f(phase, (float)elapsed);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        GLenum error = glGetError();
        if (error != GL_NO_ERROR) {
            fprintf(stderr, "GL error: 0x%x\n", error);
            goto cleanup;
        }
        SDL_GL_SwapWindow(window);
        frames++;
        elapsed = (double)(SDL_GetPerformanceCounter()-start)/SDL_GetPerformanceFrequency();
    }
    printf("Presented frames: %llu; elapsed: %.3f seconds\n", (unsigned long long)frames, elapsed);
    result = frames > 1 ? 0 : 1;
cleanup:
    if (result && *SDL_GetError()) fprintf(stderr, "SDL error: %s\n", SDL_GetError());
    if (buffer) glDeleteBuffers(1, &buffer);
    if (program) glDeleteProgram(program);
    if (vertex) glDeleteShader(vertex);
    if (fragment) glDeleteShader(fragment);
    if (context) SDL_GL_DeleteContext(context);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    return result;
}
