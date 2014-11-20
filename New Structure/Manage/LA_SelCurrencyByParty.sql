USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_SelCurrencyByParty]    Script Date: 9/8/2014 4:55:03 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE  [dbo].[LA_SelCurrencyByParty]		
	@PartyID int = 0,
	@excludeTest BIT=0
AS	
/*
Created: 20140828@Florent
Task : Get all the currency by a party
Base : Acc_SelCurrencyByLicensee
DB: DB052.bodb_licensee


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
			FROM dbo.LicenseeCust lc (nolock)
				INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID=p.OldRefID
			WHERE 
				(@PartyID = 0 OR p.PartyID = @PartyID)
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
	INNER JOIN bodb02.dbo.Exchange e with (nolock) ON t.currency = e.exchangeid
	ORDER BY 
		CurrencyName

END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_SelCurrencyByParty] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_SelCurrencyByParty] TO bodbAdminNet 
