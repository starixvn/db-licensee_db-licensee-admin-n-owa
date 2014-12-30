USE [bodb02]
GO

/****** Object:  StoredProcedure [dbo].[OAS_SelCurrencyByParty]    Script Date: 07/11/2014 10:22:23 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_SelCurrencyByParty] 
	 @PartyID 	INT = 0
	,@excludeTest 	BIT = 0
AS
/*
Created: 20140328@Florent
Task : Get all the currency by a party
Base : Acc_SelCurrencyByLicensee
DB: DB052.bodb02


Revisions:
	- 20140415@Florent: exclude get currency from Boping
	- 20141120@Winnie: change from LicenseeCust to f_SelLicenseeCust
Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	DECLARE @temp AS TABLE (currency INT)
	DECLARE @LicBoping INT

	SELECT @LicBoping = PartyID
	FROM bodb_licensee.dbo.OAS_Party
	WHERE PartyName = 'Boping'

	IF (@LicBoping != @PartyID)
	BEGIN
		INSERT INTO @temp
		SELECT DISTINCT Currency
		FROM bodb_Licensee.dbo.f_SelLicenseeCust(0) lc--(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID
		WHERE p.PartyID = @PartyID
			AND (
				@excludeTest = 0
				OR (
					@excludeTest = 1
					AND Currency <> 20
					)
				)
	END

	SELECT t.currency
		,CASE 
			WHEN t.currency = 20
				THEN 'UUS'
			WHEN t.currency = 51
				THEN 'INH'
			ELSE e.Code
			END AS CurrencyName
	FROM @temp t
	INNER JOIN dbo.exchange e WITH (NOLOCK) ON t.currency = e.exchangeid
	ORDER BY CASE 
			WHEN t.currency = 20
				THEN 'UUS'
			WHEN t.currency = 51
				THEN 'INH'
			ELSE e.Code
			END
END

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_SelCurrencyByParty] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByParty] TO bodbAdminNet 