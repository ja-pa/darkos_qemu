#include <SDL.h>
#include <SDL_opengl.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(void) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) goto fail;
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);
    SDL_Window *w = SDL_CreateWindow("Desktop GL 2.1 probe", 0, 0, 640, 480, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
    if (!w) goto fail;
    SDL_GLContext gl = SDL_GL_CreateContext(w);
    if (!gl) goto fail;
    const char *driver = SDL_GetCurrentVideoDriver();
    printf("SDL backend=%s GL vendor=%s renderer=%s version=%s\n", driver,
           glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION));
    fflush(stdout);
    if (SDL_strcasecmp(driver, "kmsdrm")) goto fail;
    FILE *maps = fopen("/proc/self/maps", "r");
    const char *output = getenv("DARKOS_MAPS");
    FILE *evidence = fopen(output ? output : "/tmp/sdl-demo.maps", "w");
    if (!maps || !evidence) goto fail;
    char line[2048]; int vendor = 0;
    while (fgets(line, sizeof line, maps)) {
        fputs(line, evidence);
        if (strstr(line, "libMali") || strstr(line, "libmali") || strstr(line, "libgo2")) vendor = 1;
    }
    fclose(maps); fclose(evidence);
    if (vendor) { fprintf(stderr, "Unexpected vendor library\n"); goto fail; }
    unsigned frames = 0; Uint32 start = SDL_GetTicks();
    int running = 1;
    while (running && SDL_GetTicks() - start < 30000) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT || (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)) running = 0;
        }
        glClearColor(0.05f, 0.08f, 0.12f, 1); glClear(GL_COLOR_BUFFER_BIT);
        glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        glRotatef((SDL_GetTicks()-start)*0.05f, 0, 0, 1);
        glBegin(GL_TRIANGLES);
        glColor3f(1,0,0); glVertex2f(-0.6f,-0.5f);
        glColor3f(0,1,0); glVertex2f(0.6f,-0.5f);
        glColor3f(0,0,1); glVertex2f(0,0.6f); glEnd();
        SDL_GL_SwapWindow(w); frames++;
    }
    printf("frames=%u elapsed_ms=%u\n", frames, SDL_GetTicks()-start);
    SDL_GL_DeleteContext(gl); SDL_DestroyWindow(w); SDL_Quit(); return 0;
fail:
    fprintf(stderr, "SDL: %s\n", SDL_GetError()); SDL_Quit(); return 1;
}
