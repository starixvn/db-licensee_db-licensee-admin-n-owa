/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20210314@Parsons
	DB: DBCUST.bodb_Licensee
	Task: Change-BaseCurrency-Of-Licensee [#FeatureID 151466]
	Description: Scripts regarding creating tables: OAS_PartyBaseCurrency.
*/
USE bodb_Licensee 
GO

CREATE TABLE [dbo].[OAS_PartyBaseCurrency](
	PartyID				int NOT NULL,
	BaseCurrencyId		tinyint NOT NULL,
	LicenseeCode		varchar(50) NOT NULL,
	FromDate			date NOT NULL,
	ToDate				date NOT NULL,
 CONSTRAINT [PK_OAS_PartyBaseCurrency] PRIMARY KEY CLUSTERED 
(
	PartyID ASC,
	BaseCurrencyId ASC,
	FromDate ASC
)) ON [OWA_DATA]
GO