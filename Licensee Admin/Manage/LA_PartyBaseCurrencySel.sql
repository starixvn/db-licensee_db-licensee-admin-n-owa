/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_PartyBaseCurrencySel]
	@PartyId INT = 0
AS
/*
	Created: 20210318@Happy
	Task : Get base currency of payer
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20210318@Happy: Initialize SP

	Params:
		- 0: get all
		- <> 0: specific party
	Example:
		EXEC dbo.LA_PartyBaseCurrencySel
*/
BEGIN
	SET NOCOUNT ON

	SELECT BaseCurrencyId AS CurrencyId,
			e.Code AS CurrencyName
	FROM dbo.OAS_PartyBaseCurrency p WITH(NOLOCK)
	LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON p.BaseCurrencyId = e.exchangeid
	WHERE (@PartyId = 0 OR PartyID = @PartyId)
END
GO