ALTER PROCEDURE  [dbo].[OAS_SelCurrencyByLicensee]		
	@LicenseeID int = 0
AS	
/*
Created: 20110423@Henry
Task : Get all the currency by a licensee
DB: DB052.bodb02


Revisions:
    - 20111028@Henry: Order by currency name
    - 20111111@Henry: allow to choose all currency
Param's Explanation:
*/

SET NOCOUNT ON
BEGIN
	declare @temp as table (currency int)

	insert into @temp
		SELECT 
			distinct Currency 
		FROM bodb_Licensee.dbo.LicenseeCust lc (nolock)
		WHERE 
			@LicenseeID = 0 OR LicenseeID = @LicenseeID

	
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
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByLicensee] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_SelCurrencyByLicensee] TO [vnteam] 