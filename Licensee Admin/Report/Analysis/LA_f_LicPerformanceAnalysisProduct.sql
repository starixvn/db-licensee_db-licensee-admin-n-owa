/*<info serverAlias="DBLIC-bodb_Licensee" selecters="bodbAdminNet" viewers="" isFunction="1" isNested="0"></info>*/
USE bodb_Licensee
GO

CREATE FUNCTION [dbo].[LA_f_AnalysisProduct] ()
RETURNS @tblProduct TABLE (
	ProductId	INT,
	ProductCode	VARCHAR(10),
	ProductName	VARCHAR(50)
)
AS
/*  Created: 20190220@Bruce
	Task : Get Charge Information for Credit
	DB: DBLIC.bodb_Licensee
	Revisions:
		- 20190220@Bruce: Create function		
*/
BEGIN
	INSERT INTO @tblProduct (Productid, ProductCode, ProductName)
	(
		SELECT 0, 'SB', 'Sportsbook'
		UNION ALL
		SELECT Productid, ProductPrefix, ProductName
		FROM dbo.Product3rd WITH(NOLOCK)
		WHERE Productid <> 16 -- Hosting fee is not supported
		UNION ALL
		SELECT 9000, 'ADJUST', 'Adjustment'
	)
	RETURN;
END