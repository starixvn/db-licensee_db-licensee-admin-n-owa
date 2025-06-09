/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee,DBACC-bodb_licensee,DBBOF-bodb_licensee,DBTP-bodb_licensee"></info>*/

/*
	Created: 20250505@Danny
	DB: DBCUST.bodb_licensee
	Description: update exchangeID column data type
*/

USE bodb_licensee

GO
ALTER TABLE OAS_PartyBaseCurrency
DROP CONSTRAINT PK_OAS_PartyBaseCurrency;

ALTER TABLE OAS_PartyBaseCurrency
ALTER COLUMN BaseCurrencyId INT NOT NULL WITH(ONLINE=ON);

ALTER TABLE OAS_PartyBaseCurrency
ADD CONSTRAINT PK_OAS_PartyBaseCurrency PRIMARY KEY CLUSTERED
(	[PartyID] ASC,
	[BaseCurrencyId] ASC,
	[FromDate] ASC
);

GO



