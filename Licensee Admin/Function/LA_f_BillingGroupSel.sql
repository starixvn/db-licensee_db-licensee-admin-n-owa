/*<info serverAlias="DBCUST-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_BillingGroupSel]()
	RETURNS @tbResult TABLE (PartyID INT)
AS

/*  Created: 20190725@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190725@Parsons: Validate billing configuration [#109600]
*/

BEGIN   
	INSERT INTO @tbResult(PartyID)
	VALUES(1), -- ONEWorks
		  (9), -- Cozni
		  (11), -- Boping
		  (98) -- Zelianta

	RETURN
END
GO