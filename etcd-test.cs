#:package dotnet-etcd@8.1.0

using System.Net;
using System.Text;
using dotnet_etcd;
using Etcdserverpb;

// Initialize client pointing to your local etcd instance
var client = new EtcdClient("http://localhost:2379");

string key = "app/settings/timeout";
string value = "30";

Console.WriteLine($"Writing key: {key} with value: {value}");

// 1. Save (Put)
await client.PutAsync(new PutRequest
{
    Key = Google.Protobuf.ByteString.CopyFromUtf8(key),
    Value = Google.Protobuf.ByteString.CopyFromUtf8(value)
});

Console.WriteLine("Data saved successfully.");

// 2. Retrieve (Get)
var getResponse = await client.GetAsync(new RangeRequest
{
    Key = Google.Protobuf.ByteString.CopyFromUtf8(key)
});

if (getResponse.Kvs.Count == 0)
{
    Console.WriteLine($"Key not found: {key}");
    return;
}

var retrievedValue = getResponse.Kvs[0].Value.ToStringUtf8();
Console.WriteLine($"Retrieved key: {key}, value: {retrievedValue}");
