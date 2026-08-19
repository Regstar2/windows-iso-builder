using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using WindowsISOBuilder.Gui.Backend;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class EventReaderTests
{
    private const string Event1 = "{\"schemaVersion\":1,\"requestId\":\"r\",\"sequence\":1,\"timestamp\":\"2026-08-18T00:00:00Z\",\"type\":\"info\",\"stage\":\"startup\",\"message\":\"Привет\",\"progress\":null}";
    private const string Event2 = "{\"schemaVersion\":1,\"requestId\":\"r\",\"sequence\":2,\"timestamp\":\"2026-08-18T00:00:01Z\",\"type\":\"progress\",\"stage\":\"download\",\"message\":\"x\",\"progress\":{\"percent\":50}}";

    [TestMethod] public async Task ReadsMultipleEvents() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1 + "\n" + Event2 + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual(2, items.Count); } finally { File.Delete(path); } }
    [TestMethod] public async Task HoldsPartialFinalLine() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1 + "\n{" ); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual(1, items.Count); } finally { File.Delete(path); } }
    [TestMethod] public async Task ParsesAppendAfterPartialData() { var path = Path.GetTempFileName(); try { var reader = new NdjsonEventReader(); var split = Event2.Length / 2; await File.WriteAllTextAsync(path, Event1 + "\n" + Event2[..split]); Assert.AreEqual(1, (await reader.ReadNewAsync(path)).Count); await File.AppendAllTextAsync(path, Event2[split..] + "\n"); var items = await reader.ReadNewAsync(path); Assert.AreEqual(1, items.Count); Assert.AreEqual(2, items[0].Sequence); } finally { File.Delete(path); } }
    [TestMethod] public async Task ReadsUtf8() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1 + "\n", new UTF8Encoding(false)); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual("Привет", items[0].Message); } finally { File.Delete(path); } }

    [TestMethod]
    public async Task HoldsIncompleteUtf8SequenceUntilRecordCompletes()
    {
        var path = Path.GetTempFileName();
        try
        {
            var reader = new NdjsonEventReader();
            var bytes = Encoding.UTF8.GetBytes(Event1 + "\n");
            var firstMultibyte = Array.FindIndex(bytes, value => value >= 0x80);
            Assert.IsTrue(firstMultibyte >= 0);
            var split = firstMultibyte + 1;

            await File.WriteAllBytesAsync(path, bytes[..split]);
            Assert.AreEqual(0, (await reader.ReadNewAsync(path)).Count);

            await using (var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
            {
                await stream.WriteAsync(bytes.AsMemory(split));
            }

            var items = await reader.ReadNewAsync(path);
            Assert.AreEqual(1, items.Count);
            Assert.AreEqual("Привет", items[0].Message);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [TestMethod] public async Task SequenceIsMonotonic() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1 + "\n" + Event2 + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.IsTrue(items[1].Sequence > items[0].Sequence); } finally { File.Delete(path); } }
    [TestMethod] public async Task DuplicateSequenceIsIgnored() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1 + "\n" + Event1 + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual(1, items.Count); } finally { File.Delete(path); } }
    [TestMethod] public async Task UnknownFieldsAreIgnored() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1[..^1] + ",\"future\":true}\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual(1, items.Count); } finally { File.Delete(path); } }
    [TestMethod] public async Task UnknownEventTypeDoesNotCrash() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1.Replace("\"info\"", "\"future\"") + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual("future", items[0].Type); } finally { File.Delete(path); } }
    [TestMethod] public async Task CancelledEventIsRead() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event1.Replace("\"info\"", "\"cancelled\"") + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual("cancelled", items[0].Type); } finally { File.Delete(path); } }
    [TestMethod] public async Task ProgressUpdateIsRead() { var path = Path.GetTempFileName(); try { await File.WriteAllTextAsync(path, Event2 + "\n"); var items = await new NdjsonEventReader().ReadNewAsync(path); Assert.AreEqual(50, items[0].Progress!.Percent); } finally { File.Delete(path); } }
}
