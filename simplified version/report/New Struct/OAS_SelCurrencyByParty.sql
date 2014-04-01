USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_SelCurrencyByParty]    Script Date: 01/04/2014 5:25:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE  [dbo].[OAS_SelCurrencyByParty]		
	@PartyID int = 0,
	@excludeTest BIT=0
AS	
/*
Created: 20140328@Florent
Task : Get all the currency by a party
Base : Acc_SelCurrencyByLicensee
DB: DB052.bodb02


Revisions:
Param's Explanation:
*/

SET NOCOUNT ON
BEGIN
	declare @temp as table (currency int)

	insert into @temp
		SELECT 
			distinct Currency 
		FROM bodb_Licensee.dbo.LicenseeCust lc (nolock)
			INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID=p.OldRefID
		WHERE 
			p.PartyID = @PartyID
			AND (@excludeTest=0 OR (@excludeTest=1 AND Currency <> 20))	
	
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
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByParty] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByParty] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_SelCurrencyByParty] TO [vnteam] 
