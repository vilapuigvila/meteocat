import XCTest
@testable import meteocatalf

final class DailySummaryParsingTests: XCTestCase {

    private let page = """
    <html><body>
    <div id="fitxa-ema"><h2>Orís</h2>
    <table><caption>Metadades estaci&oacute; meteorol&ograve;gica</caption>
      <tr><th scope="row">Municipi</th><td>Orís</td></tr></table></div>
    </body></html>
    """

    private func dailyPage(metadataFirst: Bool = false) -> String {
        let daily = """
        <table><caption>Dades di&agrave;ries de l'estaci&oacute; meteorol&ograve;gica</caption><tbody>
          <tr><th scope="row">Temperatura mitjana</th><td colspan="2"> 17.0 °C </td></tr>
          <tr><th scope="row">Temperatura màxima</th><td>20.1 °C</td><td>13:36 TU</td></tr>
          <tr><th scope="row">Precipitació acumulada</th><td colspan="2">1.4 mm</td></tr>
        </tbody></table>
        """
        let metadata = "<table><caption>Metadades estació</caption><tr><th>Municipi</th><td>Orís</td></tr></table>"
        return "<html><body><div id=\"fitxa-ema\"><h2>Orís</h2></div>"
            + (metadataFirst ? metadata + daily : daily + metadata) + "</body></html>"
    }

    func testReadsTitleValueAndTime() throws {
        let rows = try ServerData.parseDailySummary(html: dailyPage())
        XCTAssertEqual(rows.map(\.key), ["Temperatura mitjana", "Temperatura màxima", "Precipitació acumulada"])
        XCTAssertEqual(rows.map(\.value), ["17.0 °C", "20.1 °C", "1.4 mm"])
        XCTAssertEqual(rows.map(\.time), [nil, "13:36 TU", nil])
        XCTAssertEqual(Set(rows.map(\.name)), ["Orís"])
    }

    func testPageWithoutTablesMeansNoData() {
        XCTAssertThrowsError(try ServerData.parseDailySummary(html: "<html><body><h2>Orís</h2></body></html>")) {
            XCTAssertEqual($0 as? ServerData.ResponseError, .noDailyData)
        }
    }

    func testMetadataTableAloneIsNotTakenForMeasurements() {
        XCTAssertThrowsError(try ServerData.parseDailySummary(html: page)) {
            XCTAssertEqual($0 as? ServerData.ResponseError, .noDailyData)
        }
    }

    func testParsedRowsFeedTheMonthMaths() throws {
        let rows = try ServerData.parseDailySummary(html: dailyPage())
        XCTAssertEqual(StationValue.text(forKeyContaining: StationValue.averageTempKey, in: rows), "17.0 °C")
        XCTAssertEqual(StationValue.text(forKeyContaining: StationValue.accumulatedRainKey, in: rows), "1.4 mm")
    }
}
