USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_SelCurrencyByMultiParty]    Script Date: 25/09/2014 15:07:35 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE  [dbo].[OAS_SelCurrencyByMultiParty]		
	@PartyIDs VARCHAR(1000),
	@excludeTest BIT=0
AS	
/*
Created: 20140925@Florent
Task : Get all the currency by multi party
Base : Acc_SelCurrencyByLicensee
DB: DB052.bodb02


Revisions:
Param's Explanation:
*/

SET NOCOUNT ON
BEGIN
	declare @temp as table (currency int)
	
	BEGIN
		INSERT INTO @temp
			SELECT 
				distinct Currency 
			FROM bodb_Licensee.dbo.LicenseeCust lc (nolock)
				INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID=p.OldRefID
			WHERE 
				p.PartyID IN (select val FROM bodb02.dbo.strSplit(@PartyIDs,','))
				AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	
	END

	SELECT 
		t.currency, 
		CASE 
			WHEN t.currency = 20 THEN 'UUS' 
			WHEN t.currency = 51 THEN 'INH'
			ELSE e.Code 
		END AS CurrencyName
	FROM 
		@temp t
	INNER JOIN exchange e with (nolock) ON t.currency = e.exchangeid
	ORDER BY 
		CASE 
			WHEN t.currency = 20 THEN 'UUS' 
			WHEN t.currency = 51 THEN 'INH'
			ELSE e.Code 
		END

END
GO
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByMultiParty] TO [bodbLicenseeNet] 
GRANT VIEW DEFINITION ON [dbo].[OAS_SelCurrencyByMultiParty] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByMultiParty] TO bodbAdminNet 
