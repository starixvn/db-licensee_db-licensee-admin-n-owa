/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_Statement_Payment_ForexAccountSel]
AS

/*
	Created: 20230908@Danny
	DB: DBCUST.bodb_Licensee
	Task: Upload payment - Forex Account 
   
	Revisions: 
		- 20230913@Danny: Initialize SP [#193656]

	Param's Explanation:

*/

BEGIN
	SET NOCOUNT ON

	SELECT CustID, UserName
	FROM bodb02.dbo.Customer WITH(NOLOCK)
	WHERE Username IN ('PHL-Forex G/(L)','MYS-Forex G/(L)','VNM-Forex G/(L)','KHM-Forex G/(L)')


END
GO