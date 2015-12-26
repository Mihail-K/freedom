
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
protected:
    static struct After
    {
    private:
        string[] _actions = [ "*" ];

    public:
        this(string[] actions...)
        {
            _actions = actions.dup;
        }

        bool matches(string target)
        {
            foreach(action; _actions)
            {
                if(action == target || action == "*")
                {
                    return true;
                }
            }

            return false;
        }
    }

    static struct Before
    {
    private:
        string[] _actions = [ "*" ];

    public:
        this(string[] actions...)
        {
            _actions = actions.dup;
        }

        bool matches(string target)
        {
            foreach(action; _actions)
            {
                if(action == target || action == "*")
                {
                    return true;
                }
            }

            return false;
        }
    }

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

    void fireAfterCallbacks(Type : Controller)(Type controller)
    {
        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isAfterFunction!(Type, name))
            {
                alias after = getUDAs!(__traits(getMember, Type, name), Controller.After);

                static if(after.length > 0)
                {
                    foreach(descriptor; after)
                    {
                        if(descriptor.matches(controller.action))
                        {
                            __traits(getMember, controller, name)();
                            break;
                        }
                    }
                }
                else
                {
                    __traits(getMember, controller, name)();
                }
            }
        }
    }

    void fireBeforeCallbacks(Type : Controller)(Type controller)
    {
        foreach(name; __traits(derivedMembers, Type))
        {
            static if(isBeforeFunction!(Type, name))
            {
                alias after = getUDAs!(__traits(getMember, Type, name), Controller.Before);

                static if(after.length > 0)
                {
                    foreach(descriptor; after)
                    {
                        if(descriptor.matches(controller.action))
                        {
                            __traits(getMember, controller, name)();
                            break;
                        }
                    }
                }
                else
                {
                    __traits(getMember, controller, name)();
                }
            }
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
    template isAfterFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isAfterFunction = hasUDA!(__traits(getMember, Type, name), Controller.After);
        }
        else
        {
            enum isAfterFunction = false;
        }
    }

    @property
    template isBeforeFunction(Type : Controller, string name)
    {
        static if(isPublicFunction!(Type, name))
        {
            enum isBeforeFunction = hasUDA!(__traits(getMember, Type, name), Controller.Before);
        }
        else
        {
            enum isBeforeFunction = false;
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

            // Fire before-action callbacks.
            controller.fireBeforeCallbacks;

            __traits(getMember, controller, name)();

            // Fire after-action callbacks.
            controller.fireAfterCallbacks;
        };
    }

    template resource(Type : Controller)
    {
        static if(hasUDA!(Type, Resource))
        {
            alias resourceUDAs = getUDAs!(Type, Resource);
            static assert(resourceUDAs.length == 1, Type.stringof ~ " may only declare one resource id.");

            enum Resource resource = resourceUDAs[0];
        }
        else
        {
            enum string typeName = Type.stringof;

            static if(typeName.endsWith("Controller"))
            {
                enum Resource resource = Resource(typeName[0 .. $ - "Controller".length].toLower);
            }
            else
            {
                enum Resource resource = Resource(typeName.toLower);
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
