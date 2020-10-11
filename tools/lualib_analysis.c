#include <luajit-2.0/lua.h>
#include <luajit-2.0/lauxlib.h>
#include <luajit-2.0/lualib.h>
#include <stdio.h>
#include <string.h>

static int openlibs_adapter(lua_State* L) {
    luaL_openlibs(L);
    return 0;
}

static lua_CFunction str_to_lib_loader(const char* str) {
    if (strcmp(str, "base") == 0) return luaopen_base;
    if (strcmp(str, "package") == 0) return luaopen_package;
    if (strcmp(str, "string") == 0) return luaopen_string;
    if (strcmp(str, "table") == 0) return luaopen_table;
    if (strcmp(str, "math") == 0) return luaopen_math;
    if (strcmp(str, "io") == 0) return luaopen_io;
    if (strcmp(str, "os") == 0) return luaopen_os;
    if (strcmp(str, "debug") == 0) return luaopen_debug;
    if (strcmp(str, "all") == 0) return openlibs_adapter;

    // luajit
    if (strcmp(str, "bit") == 0) return luaopen_bit;
    if (strcmp(str, "jit") == 0) return luaopen_jit;
    if (strcmp(str, "ffi") == 0) return luaopen_ffi;

    return NULL;
}

int main(int argc, const char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: lualib_analysis [base|package|string|table|math|io|os|debug|bit|jit|ffi|all]\n");
        return 1;
    }

    const char* lib_name = argv[1];

    lua_State* L = luaL_newstate();

    lua_CFunction f = str_to_lib_loader(lib_name);
    if (f == NULL) {
        fprintf(stderr, "library '%s' doesn't exist\n", lib_name);
        return 1;
    }

    lua_pushcclosure(L, f, 0);
    lua_call(L, 0, 0);

    lua_pushnil(L);
    while (lua_next(L, LUA_GLOBALSINDEX) != 0) {
        lua_pushvalue(L, -2);
        lua_pushvalue(L, -2);

        size_t key_len;
        const char* key = lua_tolstring(L, -2, &key_len);

        size_t value_len;
        const char* value = lua_tolstring(L, -1, &value_len);

        const char* key_type = lua_typename(L, lua_type(L, -2));
        const char* value_type = lua_typename(L, lua_type(L, -1));
        
        fprintf(stderr, "%.*s;%s;%.*s;%s;\n", key_len, key, key_type, value_len, value, value_type);

        lua_pop(L, 3);
    }

    return 0;
}
