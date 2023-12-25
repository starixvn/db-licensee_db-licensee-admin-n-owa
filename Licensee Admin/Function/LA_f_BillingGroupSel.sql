/*<info serverAlias="DBCUST-bodb_licensee, DBLIC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_BillingGroupSel]()
	RETURNS @tbResult TABLE (PartyID INT, GroupName VARCHAR(50))
AS

/*  Created: 20190725@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee, DBLIC-bodb_licensee

	Revisions:
	- 20190725@Parsons: Validate billing configuration [#109600]
	- 20231228@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]
*/

BEGIN   
	INSERT INTO @tbResult(PartyID, GroupName)
	VALUES(1, 'ONEWorks'), -- ONEWorks
		  (9, 'Cozni'), -- Cozni
		  (11, 'Boping'), -- Boping
		  (98, 'Zelianta'), -- Zelianta
		  (962, 'JollySports') -- JollySports

	RETURN
END
GO