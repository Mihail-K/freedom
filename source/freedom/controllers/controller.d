
module freedom.controllers.controller;

import std.algorithm;
import std.array;
import std.string;
import std.traits;
import std.typecons;

import vibe.http.server;

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
        return _path.length && _path[0] != '/' ? "/" ~ _path : _path;
    }
}

alias RequestHandler = void function(HTTPServerRequest, HTTPServerResponse);

abstract class Controller
{
private:
    string _action;
    HTTPServerRequest _request;
    HTTPServerResponse _response;

public:
    @property
    string action()
    {
        return _action;
    }

    @property
    HTTPServerRequest request()
    {
        return _request;
    }

    @property
    HTTPServerResponse response()
    {
        return _response;
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
    template isPublicFunction(Type : Controller, string name)
    {
        static if(__traits(hasMember, Type, name))
        {
            static if(__traits(getProtection, __traits(getMember, Type, name)) == "public")
            {
                enum isPublicFunction = is(typeof(__traits(getMember, Type, name)) == function);
            }
            else
            {
                enum isPublicFunction = false;
            }
        }
        else
        {
            enum isPublicFunction = false;
        }
    }

    @property
    template isResourceFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isResourceFunction = hasUDA!(__traits(getMember, Type, name), Resource);
        }
        else
        {
            enum isResourceFunction = false;
        }
    }

    @property
    RequestHandler requestHandler(Type : Controller, string name)()
    {
        return function void(HTTPServerRequest request, HTTPServerResponse response)
        {
            Type controller = new Type;

            controller._action = name;
            controller._request = request;
            controller._response = response;

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
        static if(isResourceFunction!(Type, name))
        {
            alias resource = getUDAs!(Type, Resource);

            static if(resource.length > 0)
            {
                return resource[0];
            }
            else
            {
                return Resource(name.defaultResourcePath.toLower);
            }
        }
        else
        {
            static assert(0, Type.stringof ~ "." ~ name ~ " is not a resource.");
        }
    }

    @property
    ResourceDescriptor[] resources(Type : Controller)()
    {
        ResourceDescriptor[] resources;

        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isResourceFunction!(Type, name))
            {
                resources ~= ResourceDescriptor(
                    resource!(Type, name),
                    httpMethods!(Type, name),
                    requestHandler!(Type, name)
                );
            }
        }

        return resources;
    }
}
