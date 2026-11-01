using Nextshot.Core;
using Xunit;

namespace Nextshot.Core.Tests;

public class CoreInfoTests
{
    [Fact]
    public void ProductNameIsNextshot() => Assert.Equal("Nextshot", CoreInfo.ProductName);
}
