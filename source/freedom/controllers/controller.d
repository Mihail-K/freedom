
module freedom.controllers.controller;

import std.string;
import std.traits;
import std.typecons;

import vibe.http.server;

@property
string defaultResourcePath(string name)
{
    switch(name)
    {
        case "index":
        case "create":
            return "/";
        case "show":
        case "update":
        case "destroy":
            return "/:id";
        default:
            return name;
    }
}

@property
string leadingSlash(string path)
{
    return path.length && path[0] != '/' ? "/" ~ path : path;
}

struct Resource
{
private:
    string _path;

public:
    @disable this();

    this(string path)
    {
        _path = path;
    }

    Resource join(Resource other)
    {
        if(_path[$ - 1] == '/')
        {
            return Resource(_path[0 .. $ - 1] ~ other.path);
        }
        else
        {
            return Resource(_path ~ other.path);
        }
    }

    @property
    string path()
    {
        return _path.leadingSlash;
    }
}

alias RequestHandler = void function(HTTPServerRequest, HTTPServerResponse);

abstract class Controller
{
private:
    HTTPServerRequest _request;
    HTTPServerResponse _response;

package:
    @property
    RequestHandler handler(string name, this this_)()
    {
        return function void(HTTPServerRequest request, HTTPServerResponse response)
        {
            this_ controller = new this_;

            controller.request = request;
            controller.response = response;

            __traits(getMember, controller, name)();
        };
    }

    @property
    HTTPMethod[] httpMethods(string name, this this_)()
    {
        HTTPMethod[] methods;

        foreach(method; EnumMembers!HTTPMethod)
        {
            static if(hasUDA!(__traits(getMember, this_, name), method))
            {
                methods ~= method;
            }
        }

        if(methods.length == 0)
        {
            methods ~= HTTPMethod.GET;
        }

        return methods;
    }

    @property
    public HTTPServerRequest request()
    {
        return _request;
    }

    @property
    void request(HTTPServerRequest request)
    {
        _request = request;
    }

    @property
    Resource resource(this this_)()
    {
        static if(hasUDA!(this_, Resource))
        {
            alias resource = getUDAs!(this_, Resource);
            static assert(resource.length == 1, this_.stringof ~ " may only declare one resource id.");

            return resource[0];
        }
        else
        {
            enum string resource = this_.stringof;

            static if(resource.endsWith("Controller"))
            {
                return Resource(resource[0 .. $ - "Controller".length].toLower);
            }
            else
            {
                return Resource(resource.toLower);
            }
        }
    }

    @property
    Resource resource(string name, this this_)()
    {
        static if(hasUDA!(__traits(getMember, this_, name), Resource))
        {
            alias resource = getUDAs!(this_, Resource);
            static assert(resource.length == 1, this_.stringof ~ " may only declare one resource id.");

            return resource[0];
        }
        else
        {
            return Resource(name.defaultResourcePath.toLower);
        }
    }

    @property
    Tuple!(Resource, HTTPMethod[], RequestHandler)[] resources(this this_)()
    {
        this_ o = cast(this_) this;
        Tuple!(Resource, HTTPMethod[], RequestHandler)[] resources;

        foreach(name; __traits(derivedMembers, this_))
        {
            static if(__traits(getProtection, __traits(getMember, this_, name)) == "public")
            {
                static if(is(typeof(__traits(getMember, this_, name)) == function))
                {
                    resources ~= tuple(o.resource!name, o.httpMethods!name, o.handler!name);
                }
            }
        }

        return resources;
    }

    @property
    public HTTPServerResponse response()
    {
        return _response;
    }

    @property
    void response(HTTPServerResponse response)
    {
        _response = response;
    }

public:
    void head()
    {
        response.writeVoidBody;
    }

    void write(const(ubyte[]) data, string contentType = null)
    {
        response.writeBody(data, contentType);
    }

    void write(string text, string contentType = "text/plain; charset=UTF-8")
    {
        response.writeBody(text, contentType);
    }

    void write(const(ubyte[]) data, int status, string contentType = null)
    {
        response.writeBody(data, status, contentType);
    }

    void write(string text, int status, string contentType = "text/plain; charset=UTF-8")
    {
        response.writeBody(text, status, contentType);
    }

    void write(scope InputStream data, string contentType = null)
    {
        response.writeBody(data, contentType);
    }
}
