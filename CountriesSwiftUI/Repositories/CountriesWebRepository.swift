//
//  CountriesWebRepository.swift
//  CountriesSwiftUI
//

import Combine
import Foundation

protocol CountriesWebRepository: WebRepository {
    func loadCountries() -> AnyPublisher<[Country], Error>

    func loadCountryDetails(
        country: Country
    ) -> AnyPublisher<Country.Details.Intermediate, Error>
}

struct RealCountriesWebRepository: CountriesWebRepository {

    let session: URLSession
    let baseURL: String
    let apiKey: String
    let bgQueue: DispatchQueue

    private let pageSize = 100

    init(
        session: URLSession,
        baseURL: String,
        apiKey: String,
        bgQueue: DispatchQueue = DispatchQueue(
            label: "bg_parse_queue"
        )
    ) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.bgQueue = bgQueue
    }

    func loadCountries() -> AnyPublisher<[Country], Error> {
        loadCountriesPage(offset: 0)
            .map { dtos in
                dtos
                    .compactMap { $0.toDomain() }
                    .sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name)
                            == .orderedAscending
                    }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func loadCountryDetails(
        country: Country
    ) -> AnyPublisher<Country.Details.Intermediate, Error> {

        guard let encodedName = country.name.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            return Fail(error: URLError(.badURL))
                .eraseToAnyPublisher()
        }

        let fields = [
            "capitals",
            "currencies",
            "borders"
        ].joined(separator: ",")

        let path = "/names.common/\(encodedName)"
            + "?response_fields=\(fields)"
            + "&limit=1"

        return request(
            path: path,
            responseType: APIEnvelope<CountryDetailsDTO>.self
        )
        .tryMap { response in
            guard let dto = response.data.objects.first else {
                throw APIError.unexpectedResponse
            }

            return dto.intermediate
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }
}

// MARK: - Pagination

private extension RealCountriesWebRepository {

    private func loadCountriesPage(
        offset: Int
    ) -> AnyPublisher<[CountryDTO], Error> {

        let fields = [
            "names.common",
            "names.translations",
            "population",
            "flag.url_png",
            "codes.alpha_3"
        ].joined(separator: ",")

        let path = "?"
            + "response_fields=\(fields)"
            + "&limit=\(pageSize)"
            + "&offset=\(offset)"

        return request(
            path: path,
            responseType: APIEnvelope<CountryDTO>.self
        )
        .flatMap { response -> AnyPublisher<[CountryDTO], Error> in
            let currentPage = response.data.objects

            guard response.data.meta.more else {
                return Just(currentPage)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }

            return loadCountriesPage(offset: offset + pageSize)
                .map { currentPage + $0 }
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - Request

private extension RealCountriesWebRepository {

    func request<Response: Decodable>(
        path: String,
        responseType: Response.Type
    ) -> AnyPublisher<Response, Error> {

        guard let url = URL(string: baseURL + path) else {
            return Fail(error: URLError(.badURL))
                .eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        
        Logger.request(request)

        return session.dataTaskPublisher(for: request)
            .tryMap { output -> Response in

                guard let response =
                        output.response as? HTTPURLResponse else {
                    throw APIError.unexpectedResponse
                }

                Logger.response(
                    response,
                    data: output.data
                )

                guard 200..<300 ~= response.statusCode else {
                    throw APIError.unexpectedResponse
                }

                do {

                    return try JSONDecoder().decode(
                        Response.self,
                        from: output.data
                    )

                } catch {

                    Logger.error(error)
                    throw error
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - API Envelope

private struct APIEnvelope<Object: Decodable>: Decodable {
    let data: APIData<Object>
}

private struct APIData<Object: Decodable>: Decodable {
    let objects: [Object]
    let meta: APIMeta
}

private struct APIMeta: Decodable {
    let more: Bool
}

// MARK: - Country DTO

private struct CountryDTO: Decodable {
    let names: Names
    let population: Int?
    let flag: Flag?
    let codes: Codes?

    struct Names: Decodable {
        let common: String
        let translations: [String: Translation]?
    }

    struct Translation: Decodable {
        let common: String?
        let official: String?
    }

    struct Flag: Decodable {
        let urlPNG: String?

        enum CodingKeys: String, CodingKey {
            case urlPNG = "url_png"
        }
    }

    struct Codes: Decodable {
        let alpha3: String?

        enum CodingKeys: String, CodingKey {
            case alpha3 = "alpha_3"
        }
    }

    func toDomain() -> Country? {
        guard
            let alpha3Code = codes?.alpha3,
            !alpha3Code.isEmpty
        else {
            // Abkhazia ကဲ့သို့ alpha_3 အလွတ် record ကိုကျော်မည်
            return nil
        }

        let mappedTranslations: [String: String?] =
            names.translations?.mapValues { translation in
                translation.common
            } ?? [:]

        let flagURL: URL?

        if let value = flag?.urlPNG,
           !value.isEmpty {
            flagURL = URL(string: value)
        } else {
            flagURL = nil
        }

        return Country(
            name: names.common,
            translations: mappedTranslations,
            population: population ?? 0,
            flag: flagURL,
            alpha3Code: alpha3Code
        )
    }
}

// MARK: - Details DTO

private struct CountryDetailsDTO: Decodable {

    let capitals: [Capital]?
    let currencies: [CurrencyDTO]?
    let borders: [String]?

    struct Capital: Decodable {
        let name: String
    }

    struct CurrencyDTO: Decodable {
        let code: String
        let name: String
        let symbol: String?
    }

    var intermediate: Country.Details.Intermediate {
        let mappedCurrencies = (currencies ?? [])
            .map { currency in
                Country.Currency(
                    code: currency.code,
                    symbol: currency.symbol,
                    name: currency.name
                )
            }
            .sorted { $0.code < $1.code }

        return Country.Details.Intermediate(
            capital: capitals?.first?.name ?? "—",
            currencies: mappedCurrencies,
            borders: borders ?? []
        )
    }
}
