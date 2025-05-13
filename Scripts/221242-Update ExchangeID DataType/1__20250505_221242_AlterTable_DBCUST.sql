/*<info serverAlias="DBCUST-bodb_licensee"></info>*/

/*
	Created: 20250505@Danny
	DB: DBCUST.bodb_licensee
	Description: update exchangeID column data type
*/

USE bodb_licensee

GO
ALTER TABLE LA_DiscountGroupHeader
ALTER COLUMN CurrencyId INT ;

GO
ALTER TABLE LA_MinFee
ALTER COLUMN CurrencyId INT;


GO
ALTER TABLE OAS_ChargeInfo
ALTER COLUMN BaseCurrencyId INT ;


GO
ALTER TABLE OAS_ChargeInfoSub
ALTER COLUMN BaseCurrencyId INT;


--GO
--ALTER TABLE OAS_PartyBaseCurrency
--DROP CONSTRAINT PK_OAS_PartyBaseCurrency;

--ALTER TABLE OAS_PartyBaseCurrency
--ALTER COLUMN BaseCurrencyId INT NOT NULL WITH(ONLINE=ON);

--ALTER TABLE OAS_PartyBaseCurrency
--ADD CONSTRAINT PK_OAS_PartyBaseCurrency PRIMARY KEY CLUSTERED
--(	[PartyID] ASC,
--	[BaseCurrencyId] ASC,
--	[FromDate] ASC
--);

GO
ALTER TABLE OAS_PartyDetail
ALTER COLUMN BaseCurrencyId INT;


