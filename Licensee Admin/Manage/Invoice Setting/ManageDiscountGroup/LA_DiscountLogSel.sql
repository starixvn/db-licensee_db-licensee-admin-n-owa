/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_DiscountLogSel](
	@FromDate	DATE,
	@ToDate		DATE,
	@GroupId	INT = 0,
	@ActionId	INT = 0
)
AS
/*
	Created: Bruce.Bui
	Date: 2018-06-28
	Task: Select discount log detail
	DB: DBLIC.bodb_licensee
	
	Revisions:
		- 20180628@Bruce: view log for discount [#94282]
*/

BEGIN
	SET NOCOUNT ON

	SELECT l.LogId, l.LogDate, u.Username, l.ActionId, l.Doing AS [Data]
	FROM bodb_CustomerLog.dbo.UserLog_UserControl l WITH(NOLOCK)
	INNER JOIN dbo.LA_User u WITH(NOLOCK) ON l.UserID = u.UserID
	WHERE (@GroupId=0 OR l.CustID = @GroupId)
		AND (@ActionId=0 OR l.ActionID = @ActionId)
		AND l.LogDate BETWEEN @FromDate AND @ToDate
END
GO