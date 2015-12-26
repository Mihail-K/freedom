
module freedom.controllers.controller;

import std.algorithm;
import std.array;
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

package
{
    struct ResourceDescriptor
    {
        Resource resource;
        HTTPMethod[] httpMethods;
        RequestHandler requestHandler;
    }

    @property
    HTTPMethod[] httpMethods(Type : Controller, string name)()
    {
        HTTPMethod[] methods;

        foreach(method; EnumMembers!HTTPMethod)
        {
            static if(hasUDA!(__traits(getMember, Type, name), method))
            {
                methods ~= method;
            }
        }

        if(methods.length == 0)
        {
            methods ~= HTTPMethod.GET;
        }
        else
        {
            methods = sort(methods).uniq.array;
        }

        return methods;
    }

    @property
    RequestHandler requestHandler(Type : Controller, string name)()
    {
        return function void(HTTPServerRequest request, HTTPServerResponse response)
        {
            Type controller = new Type;

            controller.request = request;
            controller.response = response;

            __traits(getMember, controller, name)();
        };
    }

    @property
    Resource resource(Type : Controller)()
    {
        static if(hasUDA!(Type, Resource))
        {
            alias resource = getUDAs!(Type, Resource);
            static assert(resource.length == 1, Type.stringof ~ " may only declare one resource id.");

            return resource[0];
        }
        else
        {
            enum string resource = Type.stringof;

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
    Resource resource(Type : Controller, string name)()
    {
        static if(hasUDA!(__traits(getMember, Type, name), Resource))
        {
            alias resource = getUDAs!(Type, Resource);
            static assert(resource.length == 1, Type.stringof ~ " may only declare one resource id.");

            return resource[0];
        }
        else
        {
            return Resource(name.defaultResourcePath.toLower);
        }
    }

    @property
    ResourceDescriptor[] resources(Type : Controller)()
    {
        ResourceDescriptor[] resources;

        foreach(name; __traits(derivedMembers, Type))
        {
            static if(__traits(getProtection, __traits(getMember, Type, name)) == "public")
            {
                static if(is(typeof(__traits(getMember, Type, name)) == function))
                {
                    resources ~= ResourceDescriptor(
                        resource!(Type, name),
                        httpMethods!(Type, name),
                        requestHandler!(Type, name)
                    );
                }
            }
        }

        return resources;
    }
}
